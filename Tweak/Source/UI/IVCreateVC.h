#import <UIKit/UIKit.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Create a new container or edit an existing one (name + device model +
/// optional location entry point). Liquid Glass styling.
@interface IVCreateVC : UIViewController

/// nil == create mode; non-nil == edit mode.
- (instancetype)initWithContainer:(nullable IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
