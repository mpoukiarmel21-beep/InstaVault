#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Liquid Glass (iOS 26) helpers for UIKit. Wraps UIGlassEffect /
/// UIGlassContainerEffect when available and degrades gracefully to
/// UIBlurEffect (systemMaterial) on older systems, so the UI is never opaque.
@interface IVGlass : NSObject

/// A glass-backed view sized by constraints. `tint` may be nil.
/// `interactive` maps to UIGlassEffect.isInteractive when available.
+ (UIVisualEffectView *)glassViewWithCornerRadius:(CGFloat)radius
                                             tint:(nullable UIColor *)tint
                                      interactive:(BOOL)interactive;

/// A container that merges child glass views (UIGlassContainerEffect) with a
/// spacing, for the floating button + expanded menu morph. Falls back to a
/// plain UIView on older systems.
+ (UIVisualEffectView *)glassContainerWithSpacing:(CGFloat)spacing;

/// YES when the OS provides real Liquid Glass (UIGlassEffect exists).
+ (BOOL)liquidGlassAvailable;

@end

NS_ASSUME_NONNULL_END
