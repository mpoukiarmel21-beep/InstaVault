#import "IVThemeManager.h"
@implementation IVThemeManager
+ (instancetype)shared { static IVThemeManager *i; static dispatch_once_t o; dispatch_once(&o, ^{ i=[self new]; }); return i; }
- (UIColor *)hex:(NSString *)hex {
    NSString *c=[hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int v=0; [[NSScanner scannerWithString:c] scanHexInt:&v];
    return [UIColor colorWithRed:((v>>16)&0xFF)/255.0 green:((v>>8)&0xFF)/255.0 blue:(v&0xFF)/255.0 alpha:1];
}
@end
