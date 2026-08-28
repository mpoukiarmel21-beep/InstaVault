#import "IVFloatingButton.h"
#import "IVPanelVC.h"
#import "IVGlass.h"
#import "IVTheme.h"

#pragma mark - Passthrough overlay window

/// A tiny window that floats the button. Touches on padding (outside the button
/// container) pass through to the host app; only the button itself is live.
@interface IVOverlayWindow : UIWindow
@property (nonatomic, weak) UIView *liveView;
@end

@implementation IVOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.liveView && (hit == self.liveView || [hit isDescendantOfView:self.liveView])) return hit;
    return nil;   // pass through to the app
}
@end

#pragma mark - Top view controller (present on the app's key window)

/// Find a controller to present the panel on. Prefer the foreground scene's key
/// window, but never return nil just because no window reports isKeyWindow — some
/// hosts leave no window key, which used to make the tap silently do nothing.
static UIViewController *IVTopViewController(void) {
    UIWindow *best = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if ([w isKindOfClass:[IVOverlayWindow class]] || w.isHidden) continue;
            if (w.isKeyWindow) { best = w; break; }
            if (!best) best = w;   // fallback: first visible non-overlay window
        }
        if (best.isKeyWindow) break;
    }
    UIViewController *vc = best.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    return vc;
}

#pragma mark - Floating button

static NSString *const kIVBtnCenterKey = @"IVFloatingButtonCenter";
static const CGFloat kIVButtonSize = 60.0;
static const CGFloat kIVPad = 18.0;   // shadow padding around the button

@interface IVFloatingButton () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) IVOverlayWindow *window;
@property (nonatomic, strong) UIView *container;      // button container (live area)
@property (nonatomic, strong) UIViewController *presentedNav;   // guard double-present
@end

@implementation IVFloatingButton

+ (instancetype)shared {
    static IVFloatingButton *i;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [self new]; });
    return i;
}

- (void)show {
    if (self.window) { self.window.hidden = NO; return; }

    // Require a foreground window scene BEFORE creating anything. If we built the
    // window without one (e.g. the 2.5s fallback fired before the UI came up),
    // it would never attach to a scene AND self.window would be set — so every
    // later DidBecomeActive would hit the early-return above and the button would
    // never appear. Bail instead and let the next activation retry.
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    if (!scene) return;

    CGFloat dim = kIVButtonSize + kIVPad * 2;
    IVOverlayWindow *w = [[IVOverlayWindow alloc] initWithFrame:CGRectMake(0, 0, dim, dim)];
    w.windowLevel = UIWindowLevelAlert + 1;
    w.backgroundColor = UIColor.clearColor;
    w.windowScene = scene;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    w.rootViewController = root;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(kIVPad, kIVPad, kIVButtonSize, kIVButtonSize)];
    // Soft violet glow instead of a flat black drop shadow — reads as a premium
    // floating control rather than a plain circle.
    container.layer.shadowColor = IVTheme.accentDeep.CGColor;
    container.layer.shadowOpacity = 0.45;
    container.layer.shadowRadius = 12.0;
    container.layer.shadowOffset = CGSizeMake(0, 6);
    // Explicit circular shadow path: without it the layer derives a rectangular
    // shadow from the (square) bounds, so a round button casts a square shadow.
    container.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:container.bounds
                                                           cornerRadius:kIVButtonSize / 2.0].CGPath;

    // Glass background — NON-interactive and touch-transparent, so the button on
    // top always receives the tap. An interactive UIGlassEffect installs its own
    // gesture/interaction that could swallow the tap (the old "rien ne se passe").
    UIVisualEffectView *glass = [IVGlass glassViewWithCornerRadius:kIVButtonSize / 2.0
                                                              tint:IVTheme.accent
                                                       interactive:NO];
    glass.frame = container.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.userInteractionEnabled = NO;
    // Hairline edge so the glass reads as a crisp disc over busy content.
    glass.layer.borderWidth = 0.5;
    glass.layer.borderColor = IVTheme.hairline.CGColor;
    [container addSubview:glass];

    // The real interactive layer: a UIButton reliably turns a stationary touch
    // into an action while coexisting with the drag pan on the container.
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = container.bounds;
    btn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    UIImage *icon = [[UIImage systemImageNamed:@"square.stack.3d.up.fill" withConfiguration:cfg]
                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [btn setImage:icon forState:UIControlStateNormal];
    btn.tintColor = UIColor.whiteColor;
    btn.adjustsImageWhenHighlighted = NO;
    [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:btn];

    // VoiceOver: expose the button as a single, labelled control.
    btn.isAccessibilityElement = YES;
    btn.accessibilityLabel = @"Whamscale";
    btn.accessibilityHint = @"Ouvre la gestion des conteneurs";

    [container addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)]];

    [root.view addSubview:container];
    w.liveView = container;
    self.window = w;
    self.container = container;

    w.hidden = NO;
    [self restorePosition];
}

- (void)hide { self.window.hidden = YES; }

#pragma mark - Drag / snap / persist

- (CGRect)screenBounds {
    return self.window.screen.bounds.size.width > 0 ? self.window.screen.bounds : UIScreen.mainScreen.bounds;
}

// The overlay window is only ~90pt wide, so its OWN safeAreaInsets are ~0 — it
// doesn't span the notch or the home indicator. Read the host app's key window
// insets instead so we clamp consistently below the notch and above the home
// indicator. Falls back to typical modern-iPhone insets if none is found.
- (UIEdgeInsets)screenSafeInsets {
    UIWindowScene *scene = (UIWindowScene *)self.window.windowScene;
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        for (UIWindow *w in scene.windows) {
            if (w != self.window &&
                !UIEdgeInsetsEqualToEdgeInsets(w.safeAreaInsets, UIEdgeInsetsZero)) {
                return w.safeAreaInsets;
            }
        }
    }
    return UIEdgeInsetsMake(44.0, 0.0, 34.0, 0.0);
}

// Snap horizontally to the nearer edge and clamp vertically inside the safe
// area. Shared by drag-end and restore so both agree on the same bounds.
- (CGPoint)clampedCenter:(CGPoint)c inBounds:(CGRect)b {
    CGFloat half = self.window.bounds.size.width / 2.0;
    UIEdgeInsets safe = [self screenSafeInsets];
    c.x = (c.x < b.size.width / 2.0) ? (half + 4.0) : (b.size.width - half - 4.0);
    CGFloat minY = safe.top + half + 4.0;
    CGFloat maxY = b.size.height - safe.bottom - half - 4.0;
    c.y = MAX(minY, MIN(maxY, c.y));
    return c;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:g.view];
    CGPoint c = self.window.center;
    c.x += tr.x; c.y += tr.y;
    self.window.center = c;
    [g setTranslation:CGPointZero inView:g.view];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self snapToEdgeAndSave];
    }
}

- (void)snapToEdgeAndSave {
    CGRect b = [self screenBounds];
    CGPoint c = [self clampedCenter:self.window.center inBounds:b];
    void (^persist)(void) = ^{
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(c) forKey:kIVBtnCenterKey];
    };
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.window.center = c;
        persist();
        return;
    }
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.window.center = c; }
                     completion:^(BOOL done) { persist(); }];
}

- (void)restorePosition {
    CGRect b = [self screenBounds];
    CGFloat half = self.window.bounds.size.width / 2.0;
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kIVBtnCenterKey];
    CGPoint c = saved ? CGPointFromString(saved)
                      : CGPointMake(b.size.width - half - 4.0, b.size.height * 0.72);
    self.window.center = [self clampedCenter:c inBounds:b];
}

#pragma mark - Tap → panel

- (void)onTap {
    // Already showing the panel? Ignore (avoids double-present).
    if (self.presentedNav && self.presentedNav.presentingViewController) return;

    UIViewController *top = IVTopViewController();
    // Never present onto a controller that is busy — already presenting
    // something, or mid-transition. UIKit silently drops such a request; if we
    // had already hidden the button window, it would then stay hidden forever
    // with no tap target to bring it back. That was the "after I switch to the
    // container I just created, the menu button stops working" report: closing
    // the panel and re-tapping while the previous sheet was still dismissing (or
    // while a lingering alert owned the top VC) hid the button behind a present
    // that never happened. Bail while the button is still visible; the next tap
    // retries once the top VC is free.
    if (!top || top.presentedViewController || top.isBeingPresented || top.isBeingDismissed) return;

    // Press feedback (skipped under Reduce Motion).
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.08 animations:^{
            self.container.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL d) {
            [UIView animateWithDuration:0.12 animations:^{ self.container.transform = CGAffineTransformIdentity; }];
        }];
    }

    IVPanelVC *panel = [IVPanelVC new];
    __weak typeof(self) ws = self;
    panel.onClose = ^{ [ws showButton]; };   // restore the button when the menu closes

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:panel];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.presentationController.delegate = self;   // backup re-show on swipe-dismiss
    self.presentedNav = nav;

    // Hide the button only once the sheet is actually on screen (in the present
    // completion). If the present is ever a no-op, the window is never stranded
    // hidden behind a menu that isn't there.
    [top presentViewController:nav animated:YES completion:^{
        ws.window.hidden = YES;
    }];
}

// Idempotent: bring the button back and clear the presentation guard. Called
// from the panel's onClose (Close button) and the presentation delegate (swipe),
// so the button always returns no matter how the menu was dismissed.
- (void)showButton {
    self.window.hidden = NO;
    self.presentedNav = nil;
}

#pragma mark - UIAdaptivePresentationControllerDelegate

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self showButton];
}

@end
