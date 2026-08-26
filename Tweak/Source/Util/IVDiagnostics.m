#import "IVDiagnostics.h"
#import "IVPaths.h"

@implementation IVDiagnostics {
    NSLock *_lock;
    NSString *_logPath;
}

+ (instancetype)shared {
    static IVDiagnostics *i;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [self new]; });
    return i;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lock = [NSLock new];
    }
    return self;
}

- (NSString *)logDirectory {
    NSString *dir = [[[IVPaths realHome] stringByAppendingPathComponent:@"Documents"]
                        stringByAppendingPathComponent:@"InstaVault/logs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        NSError *err = nil;
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&err]) {
            // Can't use IVErr here (would recurse); fall back to NSLog only.
            NSLog(@"[InstaVault] log dir create failed: %@", err);
        }
    }
    return dir;
}

- (void)log:(NSString *)level msg:(NSString *)msg {
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n",
                        [NSDate date], level, msg ?: @"(nil)"];
    NSLog(@"[InstaVault] %@", line);   // also to system log for `idevicesyslog`

    [_lock lock];
    @try {
        if (!_logPath) {
            _logPath = [[self logDirectory] stringByAppendingPathComponent:@"instavault.log"];
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![fm fileExistsAtPath:_logPath]) {
            NSError *werr = nil;
            if (![data writeToFile:_logPath options:NSDataWritingAtomic error:&werr]) {
                // Can't use IVErr here (would recurse); NSLog only.
                NSLog(@"[InstaVault] log write failed (create) at %@: %@", _logPath, werr);
            }
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:_logPath];
            if (fh) {
                @try {
                    [fh seekToEndOfFile];
                    [fh writeData:data];
                } @finally {
                    [fh closeFile];
                }
            }
        }
    } @catch (NSException *ex) {
        NSLog(@"[InstaVault] log write exception: %@", ex);
    } @finally {
        [_lock unlock];
    }
}

- (void)info:(NSString *)msg { [self log:@"INFO" msg:msg]; }
- (void)error:(NSString *)msg { [self log:@"ERROR" msg:msg]; }

@end
