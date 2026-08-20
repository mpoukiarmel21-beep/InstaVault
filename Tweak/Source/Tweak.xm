#import <UIKit/UIKit.h>
#import "IVContainerManager.h"
#import "IVDeviceSpoofing.h"
#import "IVLocationSpoofing.h"
#import "IVDiagnostics.h"
#import "IVFloatingButton.h"
#import "IVContainerListVC.h"
#import "IVContainer.h"

static IVFloatingButton *_btn = nil;

static void IVAttachButton(void) {
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
    if (!kw) return;
    if (_btn) return;

    _btn = [[IVFloatingButton alloc] initWithFrame:CGRectMake(20, 100, 60, 60)];
    [_btn attach:kw];
    [_btn setCount:[IVContainerManager shared].list.count];
    if ([IVContainerManager shared].active) [_btn setHex:[IVContainerManager shared].active.color];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"IVTap" object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        IVContainerListVC *vc = [IVContainerListVC new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [kw.rootViewController presentViewController:nav animated:YES completion:nil];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:kIVActiveChanged object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        IVContainer *a = [IVContainerManager shared].active;
        if (a) [_btn setHex:a.color];
        [_btn setCount:[IVContainerManager shared].list.count];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:kIVListChanged object:nil
        queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [_btn setCount:[IVContainerManager shared].list.count];
    }];
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
