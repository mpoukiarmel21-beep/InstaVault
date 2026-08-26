#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolves every path InstaVault needs, distinguishing:
///   - realHome     : the app's true sandbox home, captured BEFORE any HOME
///                    redirect (== NSHomeDirectory() at the first line of the
///                    constructor). All shared control files live here.
///   - container root: <realHome>/Documents/Instances/<cid>/  (the redirected
///                    HOME for a non-default container).
///
/// IMPORTANT: after the HOME redirect, NSHomeDirectory() points inside the
/// active container. Never use NSHomeDirectory() to reach the shared control
/// files — always go through +realHome. This is the BUG-01 class of failure.
@interface IVPaths : NSObject

/// Capture the real home. MUST be the first thing the constructor calls,
/// before any setenv. Idempotent.
+ (void)captureRealHome;

/// The true app sandbox home (un-redirected). Falls back to NSHomeDirectory()
/// if capture somehow didn't run.
+ (NSString *)realHome;

/// <realHome>/Documents/InstaVault  (shared control dir; created on demand).
+ (NSString *)controlDir;

/// <realHome>/Documents/InstaVault/containers.plist
+ (NSString *)containersFile;

/// <realHome>/Documents/InstaVault/active.plist
+ (NSString *)activeFile;

/// <realHome>/Documents/Instances/<cid>  (a non-default container's HOME root).
+ (NSString *)containerRootForCID:(NSString *)cid;

/// Create the skeleton dirs (Documents, Library, Library/Caches,
/// Library/Preferences, tmp) under a container root. Returns NO + logs on failure.
+ (BOOL)ensureSkeletonAtRoot:(NSString *)root;

@end

NS_ASSUME_NONNULL_END
