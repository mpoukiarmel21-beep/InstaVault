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

#pragma mark - Dark surface palette (menu + action sheet)

/// Deep, violet-tinted near-black — the base background of the dark menu and the
/// custom action sheet. Reads "pro" and lets the accent and glass fills pop.
@property (class, nonatomic, readonly) UIColor *panelBackground;

/// A slightly lifted surface for cards/cells sitting on `panelBackground`.
@property (class, nonatomic, readonly) UIColor *elevatedSurface;

/// Translucent fill for secondary buttons — visible but see-through over the
/// dark base (the "boutons un peu translucides mais toujours visibles" ask).
@property (class, nonatomic, readonly) UIColor *glassFill;

/// Hairline stroke around translucent buttons/cards so they keep a crisp edge.
@property (class, nonatomic, readonly) UIColor *glassStroke;

/// Primary text on the dark surfaces (near-white).
@property (class, nonatomic, readonly) UIColor *primaryText;

/// Secondary/subtitle text on the dark surfaces (muted).
@property (class, nonatomic, readonly) UIColor *secondaryText;

@end

NS_ASSUME_NONNULL_END
