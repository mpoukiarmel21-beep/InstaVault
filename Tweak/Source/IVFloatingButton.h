#import <UIKit/UIKit.h>
@interface IVFloatingButton : UIButton
@property (nonatomic, strong) UILabel *badge;
@property (nonatomic, copy) void (^onTap)(void);
- (void)setCount:(NSInteger)c;
- (void)setHex:(NSString *)hex;
- (void)attachToView:(UIView *)v;
@end
