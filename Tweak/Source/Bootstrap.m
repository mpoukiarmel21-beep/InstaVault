#import <UIKit/UIKit.h>
#import "Core/IVPaths.h"
#import "Core/IVContainer.h"
#import "Core/IVContainerStore.h"
#import "Isolation/IVHomeRedirect.h"
#import "Isolation/IVKeychainHook.h"
#import "Isolation/IVPrefsHook.h"
#import "Spoof/IVDeviceSpoof.h"
#import "Spoof/IVDeviceIdentity.h"
#import "Spoof/IVLocaleSpoof.h"
#import "Spoof/IVLocationSpoof.h"
#import "UI/IVFloatingButton.h"
#import "Util/IVDiagnostics.h"

// The per-container keychain namespace, e.g. "IV:<cid>:". Empty for default.
static NSString *IVKeychainPrefixForContainer(IVContainer *c) {
    if (!c || c.isDefault) return @"";
    return [NSString stringWithFormat:@"IV:%@:", c.cid];
}

// Shows the floating button once the app UI is up. Idempotent; observes
// UIApplicationDidBecomeActive and also fires a delayed fallback.
static void IVScheduleFloatingButton(void) {
    void (^present)(void) = ^{
        [[IVFloatingButton shared] show];
    };
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { present(); }];
    // Fallback in case the app is already active by the time we get here.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), present);
}

// The cid this process actually booted (and applied isolation) for. Set ONCE in
// the constructor to the RESOLVED active cid — even on a degraded boot, so the
// guard below compares against what we ran as, not what we wished we ran as.
static NSString *gBootstrappedCID = nil;

// Backstop for the app-switcher WARM-RESUME leak. The constructor runs exactly
// once per COLD launch, so the HOME/keychain/CFPreferences redirects are applied
// only then. If the user switches the active container from the panel, the app
// tries to exit for a clean relaunch — but if it was only SUSPENDED (its card was
// never force-quit from the switcher) and iOS resumes it warm, the constructor
// does NOT re-run: the process keeps the OLD container's redirects while the
// on-disk activeCID now points to the newly chosen one, so the account surfaces on
// the wrong/default identity (exactly "revenu depuis le panel → le compte est
// apparu sur le compte par défaut"). Redirects can't be re-applied mid-process
// (they are one-shot at load), so on every foreground we compare the live
// activeCID to what we booted with and exit(0) on a mismatch; iOS then cold-
// launches us and the constructor applies the correct isolation. Coalesced to the
// default cid on both sides so a degraded boot (running as real/default) does NOT
// exit on every resume — only a genuine container switch trips it.
static void IVInstallStaleContainerGuard(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) {
        NSString *booted  = gBootstrappedCID.length ? gBootstrappedCID : kIVDefaultCID;
        NSString *current = [IVContainerStore shared].activeCID;
        current = current.length ? current : kIVDefaultCID;
        if (![booted isEqualToString:current]) {
            IVLog(@"stale container on resume (booted=%@ now=%@) — exiting for a clean cold relaunch",
                  booted, current);
            exit(0);
        }
    }];
}

// Task C — keep the isolated container's SESSION data lock-readable "for life".
// New files Instagram writes at runtime (cookies, tokens, WebKit/HTTPStorages,
// prefs) inherit NSFileProtectionComplete, which is unreadable once the device
// locks — so hours later a background relaunch can't read the session and the
// account looks logged out. Each time the app backgrounds (the moment fresh
// session files have just been written), re-stamp the whole active-container tree
// down to CompleteUntilFirstUserAuthentication so it survives any post-boot lock.
// Guarded by a background task so iOS grants us the run time before suspending,
// and done off the main thread. Only ever the isolated container root is passed
// in — never Instagram's real sandbox.
static void IVInstallBackgroundReprotect(NSString *containerRoot) {
    if (!containerRoot.length) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) {
        UIApplication *app = [UIApplication sharedApplication];
        __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
        task = [app beginBackgroundTaskWithName:@"IVReprotect" expirationHandler:^{
            if (task != UIBackgroundTaskInvalid) { [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
        }];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [IVPaths reapplyProtectionRecursivelyAtRoot:containerRoot];
            if (task != UIBackgroundTaskInvalid) { [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid; }
        });
    }];
}


__attribute__((constructor))
static void IVBootstrap(void) {
    @autoreleasepool {
        // 1. Capture the REAL sandbox home before any redirect touches env vars.
        [IVPaths captureRealHome];

        // 1b. Capture the REAL device chip family NOW — before IVDeviceSpoof rebinds
        //     sysctlbyname, otherwise the read would return the spoofed model and the
        //     model picker could offer cross-chip devices (an iPhone 11 as iPhone 17).
        [IVDeviceIdentity captureRealChip];

        // 2. Load the container store from the shared (real-home) control dir.
        IVContainerStore *store = [IVContainerStore shared];
        [store load];

        // 3. Resolve the active container (falls back to default).
        IVContainer *active = store.activeContainer;
        BOOL isDefault = (!active || active.isDefault);
        // Remember what we booted as (resolved cid, default-coalesced) for the
        // warm-resume stale guard installed below.
        gBootstrappedCID = [(active.cid.length ? active.cid : kIVDefaultCID) copy];
        IVLog(@"TWEAK_LOAD begin — active=%@ (%@)", active.name, active.cid);

        // 4. Isolation redirects — applied ONCE, only for non-default containers,
        //    and ATOMICALLY: the HOME redirect (files), the keychain namespace, and
        //    the CFPreferences redirect must ALL succeed together, or none takes
        //    effect. A half-applied state (e.g. files+keychain isolated but
        //    CFPreferences shared) is a cross-container identity leak: Instagram's
        //    device_id / phone_id live in NSUserDefaults, so a shared prefs store
        //    would let one container's session hints bleed into another — the exact
        //    "continue with the profile you logged in" bug. The default container
        //    keeps the real sandbox + real keychain so an existing login survives.
        BOOL isolated = NO;
        if (!isDefault) {
            BOOL homeOK  = [IVHomeRedirect applyForContainer:active];              // redirect #1: files
            BOOL keyOK   = homeOK &&
                [IVKeychainHook installWithPrefix:IVKeychainPrefixForContainer(active)]; // redirect #2: keychain
            BOOL prefsOK = keyOK && [IVPrefsHook installForContainer:active];      // redirect #3: CFPreferences
            if (homeOK && keyOK && prefsOK) {
                isolated = YES;
            } else {
                // Roll back any partial redirect so the launch runs consistently
                // on the real sandbox rather than half-isolated (split-brain leak).
                [IVHomeRedirect revertToRealHome];
                // Flag the degraded launch so the UI warns the user: a non-default
                // container was requested but we are now on the REAL account/keychain.
                store.isolationDegraded = YES;
                IVErr(@"Isolation FAILED for %@ (home=%d key=%d prefs=%d) — reverted to real sandbox to avoid split-brain leak",
                      active.cid, homeOK, keyOK, prefsOK);
            }
        } else {
            // Default container: install the keychain in HIDE mode so the real
            // account's view never includes another container's IV:-marked items.
            // This is the fix for an account appearing in the default container
            // after a container had been used: the default used to install NO
            // keychain hook and therefore enumerated the physically shared keychain,
            // surfacing every container's login (kSecAttrAccount is not namespaced).
            // Best-effort — a failure just keeps the prior passthrough, never blocks
            // launch, and never touches files/prefs (the real account stays intact).
            [IVKeychainHook installDefaultHideMode];
        }

        // 5. Device fingerprint spoof — only when isolation is actually active.
        //    Spoofing the device while files/keychain sit on the REAL account
        //    would make the primary login report a different device: pointless
        //    and suspicious. Deterministic per cid.
        if (isolated) {
            [IVDeviceSpoof installForContainer:active];
            // Locale/timezone spoof — same gate: only meaningful once files/keychain/
            // prefs are isolated. No-op when the container sets no language/region.
            [IVLocaleSpoof installForContainer:active];

            // Task C — permanent login persistence. Downgrade the whole container
            // tree to CompleteUntilFirstUserAuthentication NOW (catch any session
            // files written under Complete on a previous launch), then re-stamp on
            // every background so freshly-written session data stays lock-readable.
            // Isolated container root ONLY — never the real/default sandbox.
            NSString *root = [IVPaths containerRootForCID:active.cid];
            [IVPaths reapplyProtectionRecursivelyAtRoot:root];
            IVInstallBackgroundReprotect(root);
        }

        // 6. Location spoof — safe to install always; reads the active container
        //    live and passes through when no location is set.
        [IVLocationSpoof install];

        // 7. Floating control button, once the UI is ready.
        IVScheduleFloatingButton();

        // 8. Warm-resume backstop: force a clean cold relaunch if the active
        //    container changed while we were only suspended (app-switcher resume).
        IVInstallStaleContainerGuard();

        IVLog(@"TWEAK_LOAD complete — isolation=%@", isolated ? @"ON" : @"OFF (default/real sandbox)");
    }
}
