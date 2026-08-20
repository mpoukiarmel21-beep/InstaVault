#import "IVDiagnostics.h"
static IVDiagnostics *_inst; static NSUncaughtExceptionHandler *_prev;
@interface IVDiagnostics ()
@property (nonatomic, strong) NSMutableArray *entries;
@property (nonatomic, strong) dispatch_queue_t q;
@end
@implementation IVDiagnostics
+ (instancetype)shared { static dispatch_once_t o; dispatch_once(&o, ^{ _inst=[self new]; }); return _inst; }
- (instancetype)init { self=[super init]; if(self){_entries=[NSMutableArray new];_q=dispatch_queue_create("iv.diag",DISPATCH_QUEUE_SERIAL);} return self; }
- (void)log:(NSString *)m level:(IVLogLevel)l {
    static NSArray *labels; static dispatch_once_t lo; dispatch_once(&lo, ^{ labels=@[@"DBG",@"INF",@"WRN",@"ERR",@"CRT"]; });
    NSDateFormatter *f=[NSDateFormatter new]; f.dateFormat=@"HH:mm:ss.SSS";
    NSString *ts=[f stringFromDate:[NSDate date]];
    dispatch_async(self.q, ^{
        NSDictionary *e=@{@"t":ts,@"l":labels[l],@"m":m?:@""};
        [self.entries addObject:e]; if(self.entries.count>1000)[self.entries removeObjectAtIndex:0];
        NSLog(@"[InstaVault][%@] %@",labels[l],m);
    });
}
- (void)debug:(NSString *)m { [self log:m level:IVDebug]; }
- (void)info:(NSString *)m { [self log:m level:IVInfo]; }
- (void)warn:(NSString *)m { [self log:m level:IVWarn]; }
- (void)error:(NSString *)m { [self log:m level:IVError]; }
- (void)critical:(NSString *)m { [self log:m level:IVCritical]; }
- (void)installCrashHandler { _prev=NSGetUncaughtExceptionHandler(); NSSetUncaughtExceptionHandler(ivCrash); }
void ivCrash(NSException *e) { [[IVDiagnostics shared] critical:[NSString stringWithFormat:@"CRASH: %@",e.reason]]; if(_prev)_prev(e); }
@end
