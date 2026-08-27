#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <stdlib.h>

static NSString *gRealHome = nil;

// The data-protection class for EVERY control-plane path (control dir, its
// plists, and each container skeleton dir). Instagram provisions its container
// with com.apple.developer.default-data-protection = NSFileProtectionComplete,
// so anything we create under its sandbox INHERITS Complete by default — which
// means it is UNREADABLE while the device is locked. When iOS relaunches
// Instagram in the background during a lock (push wake / background refresh),
// our constructor's [store load] then fails to read containers.plist/active.plist,
// cannot resolve the active container, and silently degrades to the default
// (real) sandbox — the app comes back on the wrong identity and the container's
// session looks logged out. Downgrading OUR control files (never Instagram's own
// data) to CompleteUntilFirstUserAuthentication makes them readable during any
// post-boot locked relaunch, so the right container is resolved every time. It is
// never stricter than needed: these files hold only container metadata, no secrets
// (credentials live in the keychain, upgraded separately in IVKeychainHook).
//
// A #define (not a `static NSString *const`) because NSFileProtectionType values
// are extern symbols resolved at load time, so a file-scope static initialized
// from one is not a compile-time constant — the macro defers the reference to
// each (in-function) use site, where it is legal.
#define kIVFileProtection NSFileProtectionCompleteUntilFirstUserAuthentication

// Best-effort: stamp `path` with kIVFileProtection. Logs on failure but never
// aborts — a relaunch on the wrong protection class is a soft degrade, not a
// crash, and blocking here would be worse than the leak it guards.
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
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                            attributes:@{ NSFileProtectionKey: kIVFileProtection } error:&err]) {
            IVErr(@"controlDir create failed: %@", err);
        }
    } else {
        // Migration: a dir created before this fix inherited Complete — re-stamp it
        // so an already-installed user's control plane becomes lock-readable too.
        IVApplyProtection(dir);
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

    // Re-stamp the root itself, then walk the whole subtree. NSDirectoryEnumerator
    // yields relative sub-paths lazily (no giant in-memory array) and we skip its
    // per-item attribute prefetch — we only need the path, and we setAttributes
    // regardless of the current class. Best-effort: each failure is logged, never
    // aborts, so one unreadable item can't stop the rest of the session data from
    // being downgraded to lock-readable.
    IVApplyProtection(root);

    NSDirectoryEnumerator *en =
        [fm enumeratorAtURL:[NSURL fileURLWithPath:root isDirectory:YES]
 includingPropertiesForKeys:nil
                    options:0
               errorHandler:^BOOL(NSURL *url, NSError *err) {
                   IVErr(@"protection walk error at %@: %@", url.path, err);
                   return YES;   // keep going past an unreadable node
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

@end
