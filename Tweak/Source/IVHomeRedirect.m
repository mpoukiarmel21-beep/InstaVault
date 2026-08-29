#import "IVHomeRedirect.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <stdlib.h>

@implementation IVHomeRedirect

+ (BOOL)applyForContainer:(IVContainer *)container {
    if (!container || !container.cid.length) return YES;

    NSString *root = [IVPaths containerRootForCID:container.cid];
    if (![IVPaths ensureSkeletonAtRoot:root]) {
        IVErr(@"HOME redirect ABORTED: skeleton missing for %@", container.cid);
        return NO;
    }

    const char *path = root.fileSystemRepresentation;
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
