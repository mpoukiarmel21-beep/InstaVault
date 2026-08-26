#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IVActionStyle) {
    IVActionStyleDefault = 0,   // translucent glass row, light text
    IVActionStyleAccent,        // filled violet — a loud, solid state signal
    IVActionStyleAccentSoft,    // glass row, accent-tinted text + hairline: a calm
                                // primary action. Filled accent is RESERVED for
                                // "this is the active container" (state), never for
                                // an action you have not taken yet (avoids the
                                // "why is Activate already lit?" disorientation).
    IVActionStyleDestructive,   // translucent glass row, red text/symbol
};

/// One row in an IVActionSheet.
@interface IVAction : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *symbol;   // SF Symbol name
@property (nonatomic, assign, readonly) IVActionStyle style;
@property (nonatomic, copy, readonly, nullable) void (^handler)(void);

+ (instancetype)actionWithTitle:(NSString *)title
                         symbol:(nullable NSString *)symbol
                          style:(IVActionStyle)style
                        handler:(nullable void (^)(void))handler;
@end

/// A custom, dark "Liquid Glass" action sheet — a professional replacement for
/// UIAlertControllerStyleActionSheet in the app's own violet-on-dark theme.
/// Slides up from the bottom over a dimmed backdrop; tap the backdrop or Cancel
/// to dismiss. Actions run AFTER the sheet has animated away, so a handler that
/// presents its own alert never fights a still-dismissing sheet.
@interface IVActionSheet : UIViewController

- (instancetype)initWithTitle:(nullable NSString *)title
                      message:(nullable NSString *)message;

- (void)addAction:(IVAction *)action;

/// Present over `host`. A Cancel row is appended automatically.
- (void)presentFrom:(UIViewController *)host;

@end

NS_ASSUME_NONNULL_END
