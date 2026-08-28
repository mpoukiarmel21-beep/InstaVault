#import "IVHomeRedirect.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <stdlib.h>

@implementation IVHomeRedirect

+ (BOOL)applyForContainer:(IVContainer *)container {
    if (!container || container.isDefault) {
        IVLog(@"HOME redirect skipped (default container) — real sandbox in use");
        return YES;   // intentional no-op: default stays on the real sandbox
    }

    NSString *root = [IVPaths containerRootForCID:container.cid];
    if (![IVPaths ensureSkeletonAtRoot:root]) {
        IVErr(@"HOME redirect ABORTED: skeleton missing for %@", container.cid);
        return NO;   // fail safe: caller must NOT namespace the keychain either
    }

    const char *path = root.fileSystemRepresentation;
    // Order matters, but both must be set. Foundation reads CFFIXED_USER_HOME
    // first; HOME is the POSIX fallback. TMPDIR keeps NSTemporaryDirectory inside.
    setenv("CFFIXED_USER_HOME", path, 1);
    setenv("HOME", path, 1);

    NSString *tmp = [root stringByAppendingPathComponent:@"tmp"];
    setenv("TMPDIR", tmp.fileSystemRepresentation, 1);

    IVLog(@"HOME redirected -> %@", root);
    return YES;
}

+ (void)revertToRealHome {
    NSString *real = [IVPaths realHome];
    if (real.length == 0) return;
    setenv("CFFIXED_USER_HOME", real.fileSystemRepresentation, 1);
    setenv("HOME", real.fileSystemRepresentation, 1);
    NSString *tmp = [real stringByAppendingPathComponent:@"tmp"];
    setenv("TMPDIR", tmp.fileSystemRepresentation, 1);
    IVLog(@"HOME redirect reverted -> real sandbox %@", real);
}

@end
