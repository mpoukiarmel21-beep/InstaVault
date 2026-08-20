#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, IVLogLevel) { IVDebug,IVInfo,IVWarn,IVError,IVCritical };
@interface IVDiagnostics : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)m level:(IVLogLevel)l;
- (void)debug:(NSString *)m;
- (void)info:(NSString *)m;
- (void)warn:(NSString *)m;
- (void)error:(NSString *)m;
- (void)critical:(NSString *)m;
- (void)installCrashHandler;
@end
