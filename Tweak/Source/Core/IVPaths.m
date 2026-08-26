#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <stdlib.h>

static NSString *gRealHome = nil;

@implementation IVPaths

+ (void)captureRealHome {
    if (gRealHome) return;
    // Capture the REAL sandbox home before any CFFIXED_USER_HOME/HOME setenv.
    // Prefer the POSIX env var: reading getenv("HOME") does NOT prime
    // CoreFoundation's cached home directory (memoized on first resolution), so
    // a later CFFIXED_USER_HOME redirect is still honored. NSHomeDirectory() is
    // only the fallback because that call can seed the very cache we must avoid.
    const char *envHome = getenv("HOME");
    if (envHome && *envHome) {
        gRealHome = [[NSString stringWithUTF8String:envHome] copy];
    } else {
        gRealHome = [NSHomeDirectory() copy];
    }
    if (gRealHome.length) {
        // Persist for any code (or subprocess) that needs the real home after
        // the redirect — mirrors iCTK's ORIGINAL_HOME_PATH.
        setenv("ORIGINAL_HOME_PATH", gRealHome.UTF8String, 1);
    }
}

+ (NSString *)realHome {
    if (gRealHome.length) return gRealHome;
    const char *orig = getenv("ORIGINAL_HOME_PATH");
    if (orig && *orig) return [NSString stringWithUTF8String:orig];
    return NSHomeDirectory();   // last resort
}

+ (NSString *)controlDir {
    NSString *dir = [[[self realHome] stringByAppendingPathComponent:@"Documents"]
                        stringByAppendingPathComponent:@"InstaVault"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        NSError *err = nil;
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&err]) {
            IVErr(@"controlDir create failed: %@", err);
        }
    }
    return dir;
}

+ (NSString *)containersFile {
    return [[self controlDir] stringByAppendingPathComponent:@"containers.plist"];
}

+ (NSString *)activeFile {
    return [[self controlDir] stringByAppendingPathComponent:@"active.plist"];
}

+ (NSString *)containerRootForCID:(NSString *)cid {
    return [[[[self realHome] stringByAppendingPathComponent:@"Documents"]
                stringByAppendingPathComponent:@"Instances"]
                stringByAppendingPathComponent:cid];
}

+ (BOOL)ensureSkeletonAtRoot:(NSString *)root {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *subdirs = @[ @"Documents",
                                      @"Library",
                                      @"Library/Caches",
                                      @"Library/Preferences",
                                      @"tmp" ];
    for (NSString *sub in subdirs) {
        NSString *path = [root stringByAppendingPathComponent:sub];
        if ([fm fileExistsAtPath:path]) continue;
        NSError *err = nil;
        if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&err]) {
            IVErr(@"skeleton create failed at %@: %@", path, err);
            return NO;
        }
    }
    return YES;
}

@end
