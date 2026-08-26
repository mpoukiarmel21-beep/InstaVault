#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Notifications posted on the main queue after mutations.
extern NSString *const kIVContainersChanged;   // list changed (add/remove/rename)
extern NSString *const kIVActiveChanged;       // active container changed

/// Owns the container list and the active-container pointer, persisted as
/// plists in the SHARED (real-home) control dir. This is the single source of
/// truth. All disk writes are error-checked (no silent failure).
///
/// Switching the active container requires an app restart to take effect
/// (the HOME + keychain redirects are applied once at launch). The store only
/// records the choice; Bootstrap acts on it next launch.
@interface IVContainerStore : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<IVContainer *> *containers;
@property (nonatomic, readonly, nullable) IVContainer *activeContainer;
@property (nonatomic, readonly, copy) NSString *activeCID;

/// Runtime-only (never persisted): YES when the app launched in a DEGRADED state —
/// a non-default container was requested but could not be honored (its cid was
/// unresolvable at load, or Bootstrap's isolation apply failed and reverted to the
/// real sandbox). In that state the app is running on the REAL account/keychain, so
/// the UI must warn the user not to log in thinking they are isolated.
@property (nonatomic, assign) BOOL isolationDegraded;

/// Load from disk. Creates+persists the default container on first run.
/// Safe to call once early in the constructor.
- (void)load;

/// Persist the list. Returns NO and logs on failure.
- (BOOL)save;

/// Create a new container, build its on-disk skeleton, and persist.
/// Returns the container, or nil (and logs) if the skeleton could not be built
/// or the list could not be persisted — in which case nothing is added.
- (nullable IVContainer *)createWithName:(NSString *)name;
- (BOOL)renameContainer:(IVContainer *)c to:(NSString *)newName;   // NO for default/blank
- (BOOL)removeContainer:(IVContainer *)c;                          // NO for default/active

/// Records the new active cid (persisted). Does NOT re-hook — caller prompts
/// restart. Returns NO (and reverts the change in memory) if persistence fails,
/// so the in-memory state never diverges from disk.
- (BOOL)setActiveCID:(NSString *)cid;

/// Update the fake location of a container and persist. Pass nil lat/lng to
/// clear. Returns NO (and reverts in memory) if persistence fails.
- (BOOL)setLocation:(nullable NSNumber *)lat
              lng:(nullable NSNumber *)lng
             name:(nullable NSString *)name
     forContainer:(IVContainer *)c;

/// Update the spoofed device identity of a container (model identifier + its
/// marketing name + iOS marketing version) and persist. Any argument may be nil
/// to clear that field. Returns NO (and reverts every field in memory) on
/// persistence failure, so memory never diverges from disk.
- (BOOL)setDeviceModel:(nullable NSString *)deviceModel
             iosVersion:(nullable NSString *)iosVersion
          marketingName:(nullable NSString *)marketingName
           forContainer:(IVContainer *)c;

/// Update the app-language + region/country overrides of a container and persist.
/// Pass nil for either to clear it. Returns NO (and reverts in memory) on
/// persistence failure.
- (BOOL)setAppLanguage:(nullable NSString *)appLanguage
                region:(nullable NSString *)region
          forContainer:(IVContainer *)c;

/// Global reset: delete every non-default container's data + clear the list to
/// just the default. Returns NO + logs on failure.
- (BOOL)resetAll;

- (nullable IVContainer *)containerForCID:(NSString *)cid;

@end

NS_ASSUME_NONNULL_END
