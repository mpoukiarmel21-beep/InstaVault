#import <UIKit/UIKit.h>
#import "IVContainerManager.h"
#import "IVDeviceSpoofing.h"
#import "IVLocationSpoofing.h"
#import "IVDiagnostics.h"
#import "IVFloatingButton.h"
#import "IVContainerListVC.h"
#import "IVContainer.h"

@interface IVOverlayWindow : UIWindow
@end

@implementation IVOverlayWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeFirstResponder { return NO; }
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
    vc.view.userInteractionEnabled = NO;
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
        [[IVDiagnostics shared] info:@"=== InstaVault v1.0.0 ==="];
        [[IVDiagnostics shared] info:@"Tweak init"];
        [[IVDiagnostics shared] installCrashHandler];

        IVContainerManager *m = [IVContainerManager shared];
        [m load];
        if (m.active) {
            [[IVDeviceSpoofing shared] enable:m.active.device];
            if ([m.active hasLocation])
                [[IVLocationSpoofing shared] enable:m.active.location];
            [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Restored: %@", m.active.name]];
        }

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
    }
}
