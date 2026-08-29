#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <stdlib.h>

static NSString *gRealHome = nil;

// See Badoo original: downgrade OUR control files (container metadata only) to
// CompleteUntilFirstUserAuthentication so a locked-background relaunch can still
// resolve the right container. Credentials live in the keychain, not here.
#define kIVFileProtection NSFileProtectionCompleteUntilFirstUserAuthentication

static void IVApplyProtection(NSString *path) {
    if (!path.length) return;
    NSError *err = nil;
    if (![[NSFileManager defaultManager]
            setAttributes:@{ NSFileProtectionKey: kIVFileProtection }
             ofItemAtPath:path error:&err]) {
        IVErr(@"file-protection set failed at %@: %@", path, err);
    }
}

@implementation IVPaths

+ (void)captureRealHome {
    if (gRealHome) return;
    const char *envHome = getenv("HOME");
    if (envHome && *envHome) {
        gRealHome = [[NSString stringWithUTF8String:envHome] copy];
    } else {
        gRealHome = [NSHomeDirectory() copy];
    }
    if (gRealHome.length) {
        setenv("ORIGINAL_HOME_PATH", gRealHome.UTF8String, 1);
    }
}

+ (NSString *)realHome {
    if (gRealHome.length) return gRealHome;
    const char *orig = getenv("ORIGINAL_HOME_PATH");
    if (orig && *orig) return [NSString stringWithUTF8String:orig];
    return NSHomeDirectory();
}

+ (NSString *)controlDir {
    NSString *dir = [[[self realHome] stringByAppendingPathComponent:@"Documents"]
                        stringByAppendingPathComponent:@"InstaVault"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        NSError *err = nil;
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                            attributes:@{ NSFileProtectionKey: kIVFileProtection } error:&err]) {
            IVErr(@"controlDir create failed: %@", err);
        }
    } else {
        IVApplyProtection(dir);
    }
    return dir;
}

+ (NSString *)containerRootForCID:(NSString *)cid {
    return [[[[[self realHome] stringByAppendingPathComponent:@"Documents"]
                stringByAppendingPathComponent:@"InstaVault"]
                stringByAppendingPathComponent:@"Containers"]
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
        if ([fm fileExistsAtPath:path]) { IVApplyProtection(path); continue; }
        NSError *err = nil;
        if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES
                            attributes:@{ NSFileProtectionKey: kIVFileProtection } error:&err]) {
            IVErr(@"skeleton create failed at %@: %@", path, err);
            return NO;
        }
    }
    return YES;
}

+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root {
    if (!root.length) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:root]) return;
    IVApplyProtection(root);
    NSDirectoryEnumerator *en =
        [fm enumeratorAtURL:[NSURL fileURLWithPath:root isDirectory:YES]
 includingPropertiesForKeys:nil
                    options:0
               errorHandler:^BOOL(NSURL *url, NSError *err) {
                   IVErr(@"protection walk error at %@: %@", url.path, err);
                   return YES;
               }];
    NSUInteger stamped = 0;
    for (NSURL *url in en) {
        NSError *err = nil;
        if ([fm setAttributes:@{ NSFileProtectionKey: kIVFileProtection }
                 ofItemAtPath:url.path error:&err]) {
            stamped++;
        } else {
            IVErr(@"protection re-stamp failed at %@: %@", url.path, err);
        }
    }
    IVLog(@"reapplied protection to %lu item(s) under %@",
          (unsigned long)stamped, root.lastPathComponent);
}

+ (NSString *)cameraDir {
    NSString *dir = [[self controlDir] stringByAppendingPathComponent:@"Cameras"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        NSError *err = nil;
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                            attributes:@{ NSFileProtectionKey: kIVFileProtection } error:&err]) {
            IVErr(@"cameraDir create failed: %@", err);
        }
    } else {
        IVApplyProtection(dir);
    }
    return dir;
}

+ (NSString *)globalCameraVideoPath {
    return [[self cameraDir] stringByAppendingPathComponent:@"global.mov"];
}

+ (BOOL)hasGlobalCameraVideo {
    NSString *p = [self globalCameraVideoPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    return [fm fileExistsAtPath:p isDirectory:&isDir] && !isDir &&
           [[fm attributesOfItemAtPath:p error:NULL] fileSize] > 0;
}

+ (BOOL)importGlobalCameraVideoFromURL:(NSURL *)src {
    if (!src) return NO;
    NSString *dst = [self globalCameraVideoPath];
    if (!dst.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if ([fm fileExistsAtPath:dst]) {
        if (![fm removeItemAtPath:dst error:&err]) {
            IVErr(@"importGlobalCameraVideo: failed to remove existing %@: %@", dst, err);
            return NO;
        }
    }
    if (![fm copyItemAtURL:src toURL:[NSURL fileURLWithPath:dst] error:&err]) {
        IVErr(@"importGlobalCameraVideo: copy failed %@ -> %@: %@", src.path, dst, err);
        [fm removeItemAtPath:dst error:NULL];
        return NO;
    }
    IVApplyProtection(dst);
    IVLog(@"importGlobalCameraVideo: stored global video (%llu bytes)",
          (unsigned long long)[[fm attributesOfItemAtPath:dst error:NULL] fileSize]);
    return YES;
}

+ (void)removeGlobalCameraVideo {
    NSString *dst = [self globalCameraVideoPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:dst]) {
        NSError *err = nil;
        if (![fm removeItemAtPath:dst error:&err]) {
            IVErr(@"removeGlobalCameraVideo: failed to remove %@: %@", dst, err);
        }
    }
}

@end
