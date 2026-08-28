#import "IVGlass.h"

@implementation IVGlass

+ (BOOL)liquidGlassAvailable {
    return NSClassFromString(@"UIGlassEffect") != nil;
}

+ (UIVisualEffectView *)glassViewWithCornerRadius:(CGFloat)radius
                                             tint:(UIColor *)tint
                                      interactive:(BOOL)interactive {
    // Accessibility: when Reduce Transparency is on, translucency hurts legibility.
    // Skip the blur/glass entirely and fill the content view with an opaque tint.
    BOOL reduceTransparency = UIAccessibilityIsReduceTransparencyEnabled();
    UIVisualEffect *effect = nil;

    Class glassCls = reduceTransparency ? nil : NSClassFromString(@"UIGlassEffect");
    if (glassCls) {
        // iOS 26 Liquid Glass. Built via runtime so the project still compiles
        // against pre-26 SDKs.
        id glass = [[glassCls alloc] init];
        @try {
            if (tint) [glass setValue:tint forKey:@"tintColor"];
            [glass setValue:@(interactive) forKey:@"interactive"];
        } @catch (NSException *e) {
            // Don't swallow silently: a changed KVC key would otherwise degrade
            // the glass invisibly. Log and continue with the untinted effect.
            NSLog(@"[InstaVault] UIGlassEffect KVC failed (%@) — continuing without tint/interactive", e.reason);
        }
        effect = glass;
    } else if (!reduceTransparency) {
        // Graceful fallback on pre-26: never opaque.
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }

    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.layer.cornerRadius = radius;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
    if (reduceTransparency) {
        // Opaque, high-contrast fill in place of the translucency.
        v.contentView.backgroundColor = tint ?: UIColor.systemPurpleColor;
    } else if (!glassCls && tint) {
        // Tint the blur fallback subtly so prominence still reads.
        v.contentView.backgroundColor = [tint colorWithAlphaComponent:0.18];
    }
    return v;
}

+ (UIVisualEffectView *)glassContainerWithSpacing:(CGFloat)spacing {
    Class containerCls = NSClassFromString(@"UIGlassContainerEffect");
    if (containerCls) {
        id effect = [[containerCls alloc] init];
        @try { [effect setValue:@(spacing) forKey:@"spacing"]; } @catch (__unused NSException *e) {}
        UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
        v.translatesAutoresizingMaskIntoConstraints = NO;
        return v;
    }
    // Fallback: transparent passthrough container.
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:nil];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = UIColor.clearColor;
    return v;
}

@end
