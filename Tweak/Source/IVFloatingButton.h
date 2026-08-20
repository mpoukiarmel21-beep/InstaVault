#import <UIKit/UIKit.h>
@interface IVFloatingButton : UIButton
@property (nonatomic, strong) UILabel *badge;
- (void)setCount:(NSInteger)c;
- (void)setHex:(NSString *)hex;
- (void)attachToView:(UIView *)v;
@end
