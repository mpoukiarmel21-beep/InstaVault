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
        }

        // 6. Location spoof — safe to install always; reads the active container
        //    live and passes through when no location is set.
        [IVLocationSpoof install];

        // 7. Floating control button, once the UI is ready.
        IVScheduleFloatingButton();

        IVLog(@"TWEAK_LOAD complete — isolation=%@", isolated ? @"ON" : @"OFF (default/real sandbox)");
    }
}
