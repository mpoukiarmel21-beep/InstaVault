#import <UIKit/UIKit.h>
@interface IVFloatingButton : UIButton
@property (nonatomic, copy) void (^onTap)(void);
- (void)setCount:(NSUInteger)c;
- (void)setHex:(NSString *)hex;
- (void)attachToView:(UIView *)v;
@end
