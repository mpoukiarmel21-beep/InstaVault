#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The container manager panel (Liquid Glass). Lists containers with the active
/// one highlighted, and offers: create, rename, delete, set location, activate
/// (prompts restart), and global reset. Presented modally from the floating button.
@interface IVPanelVC : UIViewController

/// Called when the panel is actually dismissed (Close button or swipe-down),
/// NOT when a child is pushed. The floating button uses it to re-show itself.
@property (nonatomic, copy, nullable) void (^onClose)(void);

@end

NS_ASSUME_NONNULL_END
