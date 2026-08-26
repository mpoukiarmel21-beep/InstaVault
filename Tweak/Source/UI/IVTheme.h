#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Single source of truth for InstaVault's palette. Every screen pulls its
/// accent from here so the brand violet is identical across the floating
/// button, the panel, the create sheet and the map picker — instead of a raw
/// RGB violet in one file and systemPurple in the next (the "colors aren't
/// managed" complaint).
@interface IVTheme : NSObject

/// Primary brand accent (violet). Tints, active marker, primary call-to-action.
@property (class, nonatomic, readonly) UIColor *accent;

/// Deeper companion shade — gradients, pressed states, the button's soft glow.
@property (class, nonatomic, readonly) UIColor *accentDeep;

/// Foreground that sits on top of `accent` (white), with enough contrast for AA.
@property (class, nonatomic, readonly) UIColor *onAccent;

/// A hairline stroke for glass edges (white, low alpha) so a disc reads crisply
/// over busy content.
@property (class, nonatomic, readonly) UIColor *hairline;

@end

NS_ASSUME_NONNULL_END
