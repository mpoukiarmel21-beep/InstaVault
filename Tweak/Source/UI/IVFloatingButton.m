#import "IVFloatingButton.h"
#import "IVPanelVC.h"
#import "IVGlass.h"

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

static UIViewController *IVTopViewController(void) {
    UIWindow *key = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow && ![w isKindOfClass:[IVOverlayWindow class]]) { key = w; break; }
        }
        if (key) break;
    }
    UIViewController *vc = key.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - Floating button

static NSString *const kIVBtnCenterKey = @"IVFloatingButtonCenter";
static const CGFloat kIVButtonSize = 58.0;
static const CGFloat kIVPad = 16.0;   // shadow padding around the button

@interface IVFloatingButton ()
@property (nonatomic, strong) IVOverlayWindow *window;
@property (nonatomic, strong) UIView *container;   // button container (live area)
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
    container.layer.shadowColor = UIColor.blackColor.CGColor;
    container.layer.shadowOpacity = 0.35;
    container.layer.shadowRadius = 8.0;
    container.layer.shadowOffset = CGSizeMake(0, 3);
    // Explicit circular shadow path: without it the layer derives a rectangular
    // shadow from the (square) bounds, so a round button casts a square shadow.
    container.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:container.bounds
                                                           cornerRadius:kIVButtonSize / 2.0].CGPath;

    UIVisualEffectView *glass = [IVGlass glassViewWithCornerRadius:kIVButtonSize / 2.0
                                                              tint:UIColor.systemPurpleColor
                                                       interactive:YES];
    glass.frame = container.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:glass];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.stack.3d.up.fill"]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [glass.contentView addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:glass.contentView.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:glass.contentView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:26.0],
        [icon.heightAnchor constraintEqualToConstant:26.0],
    ]];

    [root.view addSubview:container];
    w.liveView = container;
    self.window = w;
    self.container = container;

    // VoiceOver: expose the button as a single, labelled control. Without this
    // the glass container is invisible to assistive tech.
    container.isAccessibilityElement = YES;
    container.accessibilityLabel = @"InstaVault";
    container.accessibilityHint = @"Ouvre la gestion des conteneurs";
    container.accessibilityTraits = UIAccessibilityTraitButton;

    [container addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)]];
    [container addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)]];

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

- (void)onTap:(UITapGestureRecognizer *)g {
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.08 animations:^{
            self.container.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL d) {
            [UIView animateWithDuration:0.12 animations:^{ self.container.transform = CGAffineTransformIdentity; }];
        }];
    }

    UIViewController *top = IVTopViewController();
    if (!top) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[IVPanelVC new]];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [top presentViewController:nav animated:YES completion:nil];
}

@end
