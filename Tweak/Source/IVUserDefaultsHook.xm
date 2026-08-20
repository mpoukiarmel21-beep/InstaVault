#import <Foundation/Foundation.h>
%hook NSUserDefaults
- (instancetype)initWithSuiteName:(NSString *)s {
    IVContainer *a=[IVContainerManager shared].active;
    if(a&&s)return %orig([NSString stringWithFormat:@"%@_%@",s,a.cid]);
    return %orig;
}
+ (NSUserDefaults *)standardUserDefaults {
    IVContainer *a=[IVContainerManager shared].active;
    if(a)return [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"com.ig.%@",a.cid]];
    return %orig;
}
%end
