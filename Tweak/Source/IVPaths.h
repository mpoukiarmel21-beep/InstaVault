#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolves every path InstaVault needs, distinguishing:
///   - realHome     : the app's true sandbox home, captured BEFORE any HOME
///                     redirect (== NSHomeDirectory() at the first line of the
///                     constructor). All shared control files live here.
///   - container root: <realHome>/Documents/InstaVault/Containers/<cid>/  (the
///                     redirected HOME for an active container; matches
///                     IVContainer.sandbox so existing data is preserved).
///
/// IMPORTANT: after the HOME redirect, NSHomeDirectory() points inside the
/// active container. Never use NSHomeDirectory() to reach the shared control
/// files — always go through +realHome.
@interface IVPaths : NSObject

+ (void)captureRealHome;
+ (NSString *)realHome;

/// <realHome>/Documents/InstaVault  (shared control dir; created on demand).
+ (NSString *)controlDir;

/// <realHome>/Documents/InstaVault/Containers/<cid> (an active container's HOME root).
+ (NSString *)containerRootForCID:(NSString *)cid;

+ (BOOL)ensureSkeletonAtRoot:(NSString *)root;
+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root;

/// <controlDir>/Cameras  (virtual-camera videos; created on demand, lock-readable).
+ (NSString *)cameraDir;

#pragma mark - Global virtual-camera video (shared by ALL containers)

/// <controlDir>/Cameras/global.mov — the SINGLE verification video shared by every
/// container. Existence of this file IS the "camera configured" state.
+ (NSString *)globalCameraVideoPath;
+ (BOOL)hasGlobalCameraVideo;
+ (BOOL)importGlobalCameraVideoFromURL:(NSURL *)src;
+ (void)removeGlobalCameraVideo;

@end

NS_ASSUME_NONNULL_END
