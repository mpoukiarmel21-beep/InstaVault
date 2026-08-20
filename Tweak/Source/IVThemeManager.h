#import <UIKit/UIKit.h>
@interface IVThemeManager : NSObject
+ (instancetype)shared;
- (UIColor *)hex:(NSString *)hex;
@end
