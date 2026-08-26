#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Per-container device fingerprint spoofing (plan-directeur §7). Everything is
/// derived deterministically from SHA256(cid) so a container's identity is
/// stable across launches and unique across containers.
///
/// Honest scope: this masks locally-readable identifiers only. Instagram binds
/// accounts to its OWN stored tokens (device_id, phone_id, X-MID, sessionid),
/// which are isolated by the HOME + keychain redirects, not by hardware spoofing.
@interface IVDeviceSpoof : NSObject

/// Install IDFV/IDFA swizzles + sysctl/uname C hooks + UIScreen/locale spoofing
/// for the given container. No-op for the default container. Run once at launch.
+ (void)installForContainer:(IVContainer *)container;

/// The device model this container presents (explicit override or seed-derived).
+ (NSString *)effectiveModelForContainer:(IVContainer *)container;

/// Valid iOS 26 device model identifiers (A12+). Used by the create/edit UI.
+ (NSArray<NSString *> *)availableModels;

@end

NS_ASSUME_NONNULL_END
