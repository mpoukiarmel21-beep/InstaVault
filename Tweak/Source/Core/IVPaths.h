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

/// Recursively (re-)stamp every file and directory under `root` with
/// NSFileProtectionCompleteUntilFirstUserAuthentication. Instagram's sandbox
/// defaults NEW files to NSFileProtectionComplete (unreadable while the device is
/// locked), so a container's runtime-written SESSION data (cookies, tokens,
/// WebKit/HTTPStorages, prefs) inherits Complete and becomes unreadable after a
/// lock — the app relaunches unable to read the session and the account looks
/// "logged out on its own hours later". Downgrading the whole active-container
/// tree to CompleteUntilFirstUserAuthentication keeps the session readable through
/// every post-boot lock, so a login persists indefinitely. Best-effort per item
/// (logs, never aborts). MUST only be called for a non-default container root —
/// never Instagram's real sandbox.
+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root;

/// Wipe the REAL (default/principal) account's on-disk session surfaces under
/// realHome — the HTTP cookie jar (Library/Cookies), NSURLSession storage
/// (Library/HTTPStorages) and web-view data (Library/WebKit) — where Instagram's
/// logged-in session persists for the un-isolated account. A global reset calls
/// this so "réinitialiser" clears the principal account's cookies too, not just
/// the containers' (whose surfaces live under their own container root and are
/// removed with that tree). Best-effort per path (logs, never aborts); returns NO
/// if any surface existed but could not be removed. ONLY touches realHome/Library
/// session dirs — never the control plane (realHome/Documents/InstaVault) nor any
/// container root. Instagram recreates these dirs empty on next launch.
+ (BOOL)wipeRealSessionFiles;

@end

NS_ASSUME_NONNULL_END
