#import <UIKit/UIKit.h>
#import "IVContainerManager.h"
#import "IVDeviceSpoofing.h"
#import "IVLocationSpoofing.h"
#import "IVDiagnostics.h"
#import "IVFloatingButton.h"
#import "IVContainerListVC.h"
#import "IVContainer.h"
#import "IVPaths.h"
#import "IVHomeRedirect.h"
#import "IVKeychainHook.h"
#import "IVPrefsHook.h"
#import "IVAppGroupHook.h"
#import "IVHardening.h"
#import "IVLocaleSpoof.h"
#import "IVCameraHook.h"

// The cid this process actually booted (and applied isolation) for. Set ONCE in
// the constructor to the RESOLVED active cid — even on a degraded boot, so the
// guard below compares against what we ran as, not what we wished we ran as.
static NSString *gBootstrappedCID = nil;

// Backstop for the app-switcher WARM-RESUME leak. The constructor runs exactly
// once per COLD launch, so the HOME/keychain/CFPreferences/App-Group redirects are
// applied only then. If the user switches the active container from the panel, the
// process exits for a clean cold relaunch that re-applies isolation. But if the
// change happened while the app was only SUSPENDED (its card never force-quit from
// the switcher) and iOS resumes it warm, the constructor does NOT re-run: the
// process keeps the OLD container's redirects while the on-disk activeCID now
// points to the newly chosen one, so the account surfaces on the wrong/default
// identity. Redirects can't be re-applied mid-process (one-shot at load), so on
// every foreground we compare the live active to what we booted with and exit(0)
// on a mismatch; iOS then cold-launches us and the constructor applies the correct
// isolation.
static void IVInstallStaleContainerGuard(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) {
        NSString *booted  = gBootstrappedCID ?: @"";
        IVContainer *m    = [IVContainerManager shared].active;
        NSString *current = m.cid ?: @"";
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
// account looks logged out. Each time the app backgrounds, re-stamp the whole
// active-container tree down to CompleteUntilFirstUserAuthentication so it
// survives any post-boot lock. Only the isolated container root is passed in —
// never Instagram's real sandbox.
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

@interface IVOverlayWindow : UIWindow
@end

@implementation IVOverlayWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeFirstResponder { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static IVFloatingButton *_btn = nil;
static IVOverlayWindow *_overlay = nil;

static UIWindow *IVKeyWindow(void) {
    UIWindow *kw = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (sc.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in sc.windows) { if (w.isKeyWindow) return w; }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([UIApplication sharedApplication].keyWindow) return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.hidden && w.windowLevel == 0) return w;
    }
    return nil;
}

static void IVEnsureOverlay(void) {
    if (_overlay) return;
    UIWindowScene *scene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (sc.activationState == UISceneActivationStateForegroundActive) {
                scene = sc;
                break;
            }
        }
    }
    if (!scene) return;
    _overlay = [[IVOverlayWindow alloc] initWithWindowScene:scene];
    _overlay.frame = [UIScreen mainScreen].bounds;
    _overlay.windowLevel = UIWindowLevelStatusBar + 1;
    _overlay.backgroundColor = [UIColor clearColor];
    _overlay.hidden = NO;
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.userInteractionEnabled = YES;
    _overlay.rootViewController = vc;
}

static void IVAttachButton(void) {
    IVEnsureOverlay();
    if (!_overlay) return;

    if (!_btn) {
        _btn = [[IVFloatingButton alloc] initWithFrame:CGRectMake(20, 100, 60, 60)];
        __weak IVFloatingButton *wbtn = _btn;
        _btn.onTap = ^{
            IVFloatingButton *b = wbtn;
            if (!b) return;
            UIWindow *kw = IVKeyWindow();
            UIViewController *top = kw.rootViewController;
            if (!top) return;
            while (top.presentedViewController) top = top.presentedViewController;
            IVContainerListVC *vc = [IVContainerListVC new];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [top presentViewController:nav animated:YES completion:nil];
        };
        [_btn setCount:[IVContainerManager shared].list.count];
        if ([IVContainerManager shared].active) [_btn setHex:[IVContainerManager shared].active.color];
    }

    UIView *host = _overlay.rootViewController.view;
    if (_btn.superview != host) {
        [_btn removeFromSuperview];
        [_btn attachToView:host];
    }
}

__attribute__((constructor))
static void IVInit() {
    @autoreleasepool {
        NSLog(@"[InstaVault] Loaded");
        [[IVDiagnostics shared] info:@"=== InstaVault v2.0.0 ==="];
        [[IVDiagnostics shared] info:@"Tweak init"];
        [[IVDiagnostics shared] installCrashHandler];

        // 1. Capture the REAL sandbox home before any redirect touches env vars.
        [IVPaths captureRealHome];

        IVContainerManager *m = [IVContainerManager shared];
        [m load];

        // Resolve the active container. nil == the REAL Instagram account (stays on
        // the real sandbox + real keychain). Non-nil == an isolated container.
        IVContainer *active = m.active;
        BOOL isolated = NO;

        if (active) {
            [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Restored: %@", active.name]];

            // Isolation redirects — applied ONCE, only for an active container, and
            // ATOMICALLY: the HOME redirect (files), the keychain namespace, the
            // CFPreferences redirect, and the App Group container redirect must ALL
            // succeed together, or none takes effect. A half-applied state is a
            // cross-container identity leak. On any failure we roll back to the real
            // sandbox rather than launch half-isolated.
            BOOL homeOK  = [IVHomeRedirect applyForContainer:active];
            BOOL keyOK   = homeOK && [IVKeychainHook installWithPrefix:[NSString stringWithFormat:@"IV:%@:", active.cid]];
            BOOL prefsOK = keyOK && [IVPrefsHook installForContainer:active];
            BOOL groupOK = prefsOK && [IVAppGroupHook installForContainer:active];
            if (homeOK && keyOK && prefsOK && groupOK) {
                isolated = YES;
            } else {
                [IVHomeRedirect revertToRealHome];
                IVErr(@"Isolation FAILED for %@ (home=%d key=%d prefs=%d group=%d) — reverted to real sandbox to avoid split-brain leak",
                      active.cid, homeOK, keyOK, prefsOK, groupOK);
            }
        } else {
            // No active container: install the keychain in HIDE mode so the real
            // account's view never includes another container's IV:-marked items.
            // Best-effort — a failure just keeps the prior passthrough, never blocks
            // launch, and never touches files/prefs (the real account stays intact).
            [IVKeychainHook installDefaultHideMode];
        }

        // Remember what we booted as, for the warm-resume stale guard.
        gBootstrappedCID = [active.cid copy];

        // Device/location/locale/timezone spoofing + hardening — only when isolation
        // is actually active. Spoofing the device while files/keychain sit on the
        // real account would make the primary login report a different device.
        if (isolated && active) {
            [[IVDeviceSpoofing shared] enable:active.device];
            if ([active hasLocation]) [[IVLocationSpoofing shared] enable:active.location];
            [IVLocaleSpoof installForContainer:active];
            [IVHardening installForContainer:active];

            NSString *root = [IVPaths containerRootForCID:active.cid];
            [IVPaths reapplyProtectionRecursivelyAtRoot:root];
            IVInstallBackgroundReprotect(root);
        }

        // Global virtual camera — GLOBAL, not gated to isolation: one shared
        // verification video for every container. No-op (real camera untouched)
        // when no global video is configured.
        [IVCameraHook installGlobal];

        [[NSNotificationCenter defaultCenter] addObserverForName:kIVActiveChanged object:nil
            queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if (!_btn) return;
            IVContainer *a = [IVContainerManager shared].active;
            if (a) [_btn setHex:a.color];
            [_btn setCount:[IVContainerManager shared].list.count];
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:kIVListChanged object:nil
            queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if (!_btn) return;
            [_btn setCount:[IVContainerManager shared].list.count];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            for (int i = 1; i <= 10; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    IVAttachButton();
                });
            }
            [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
                IVAttachButton();
            }];
        });

        // Warm-resume backstop: force a clean cold relaunch if the active container
        // changed while we were only suspended (app-switcher resume).
        IVInstallStaleContainerGuard();
    }
}