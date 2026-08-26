#import <UIKit/UIKit.h>
#import "Core/IVPaths.h"
#import "Core/IVContainer.h"
#import "Core/IVContainerStore.h"
#import "Isolation/IVHomeRedirect.h"
#import "Isolation/IVKeychainHook.h"
#import "Spoof/IVDeviceSpoof.h"
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

        // 2. Load the container store from the shared (real-home) control dir.
        IVContainerStore *store = [IVContainerStore shared];
        [store load];

        // 3. Resolve the active container (falls back to default).
        IVContainer *active = store.activeContainer;
        BOOL isDefault = (!active || active.isDefault);
        IVLog(@"TWEAK_LOAD begin — active=%@ (%@)", active.name, active.cid);

        // 4. Isolation redirects — applied ONCE, only for non-default containers,
        //    and ATOMICALLY: the HOME redirect (files) and the keychain namespace
        //    must succeed together, or neither takes effect. A half-applied state
        //    (files isolated but keychain shared, or vice versa) is a
        //    cross-container credential leak. The default container keeps the
        //    real sandbox + real keychain so an existing Instagram login survives.
        BOOL isolated = NO;
        if (!isDefault) {
            BOOL homeOK = [IVHomeRedirect applyForContainer:active];              // redirect #1: files
            BOOL keyOK  = homeOK &&
                [IVKeychainHook installWithPrefix:IVKeychainPrefixForContainer(active)]; // redirect #2: keychain
            if (homeOK && keyOK) {
                isolated = YES;
            } else {
                // Roll back any partial redirect so the launch runs consistently
                // on the real sandbox rather than half-isolated (split-brain leak).
                [IVHomeRedirect revertToRealHome];
                IVErr(@"Isolation FAILED for %@ (home=%d key=%d) — reverted to real sandbox to avoid split-brain leak",
                      active.cid, homeOK, keyOK);
            }
        }

        // 5. Device fingerprint spoof — only when isolation is actually active.
        //    Spoofing the device while files/keychain sit on the REAL account
        //    would make the primary login report a different device: pointless
        //    and suspicious. Deterministic per cid.
        if (isolated) {
            [IVDeviceSpoof installForContainer:active];
        }

        // 6. Location spoof — safe to install always; reads the active container
        //    live and passes through when no location is set.
        [IVLocationSpoof install];

        // 7. Floating control button, once the UI is ready.
        IVScheduleFloatingButton();

        IVLog(@"TWEAK_LOAD complete — isolation=%@", isolated ? @"ON" : @"OFF (default/real sandbox)");
    }
}
