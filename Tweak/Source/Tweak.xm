#import <UIKit/UIKit.h>
#import "IVContainerManager.h"
#import "IVDeviceSpoofing.h"
#import "IVLocationSpoofing.h"
#import "IVDiagnostics.h"
#import "IVFloatingButton.h"
#import "IVContainerListVC.h"
#import "IVContainer.h"

static IVFloatingButton *_btn = nil;
static BOOL _observersRegistered = NO;

static void IVAttachButton(void);

static UIWindow *IVKeyWindow(void) {
    UIWindow *kw = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (sc.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in sc.windows) { if (w.isKeyWindow) { kw = w; break; } }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!kw) kw = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    return kw;
}

static void IVRegisterObservers(void) {
    if (_observersRegistered) return;
    _observersRegistered = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    [nc addObserverForName:@"IVTap" object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        UIWindow *kw = IVKeyWindow();
        if (!kw) return;
        IVContainerListVC *vc = [IVContainerListVC new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [kw.rootViewController presentViewController:nav animated:YES completion:nil];
    }];
    [nc addObserverForName:kIVActiveChanged object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        IVContainer *a = [IVContainerManager shared].active;
        if (a) [_btn setHex:a.color];
        [_btn setCount:[IVContainerManager shared].list.count];
    }];
    [nc addObserverForName:kIVListChanged object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [_btn setCount:[IVContainerManager shared].list.count];
    }];
    [nc addObserverForName:UIWindowDidBecomeKeyNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        IVAttachButton();
    }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        IVAttachButton();
    }];
}

static void IVAttachButton(void) {
    UIWindow *kw = IVKeyWindow();
    if (!kw) return;

    if (!_btn) {
        _btn = [[IVFloatingButton alloc] initWithFrame:CGRectMake(20, 100, 60, 60)];
        [_btn setCount:[IVContainerManager shared].list.count];
        if ([IVContainerManager shared].active) [_btn setHex:[IVContainerManager shared].active.color];
        IVRegisterObservers();
    }

    if (_btn.superview != kw) {
        [_btn removeFromSuperview];
        [_btn attach:kw];
    }
}

static void IVTryAttach(int remaining) {
    if (remaining <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        IVAttachButton();
        if (!_btn) IVTryAttach(remaining - 1);
    });
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
        dispatch_async(dispatch_get_main_queue(), ^{
            IVTryAttach(20);
        });
    }
}
