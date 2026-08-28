#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Per-container device fingerprint spoofing (plan-directeur §7). Everything is
/// derived deterministically from SHA256(cid) so a container's identity is
/// stable across launches and unique across containers.
///
/// Surfaces answered (all gated on active isolation, no-op for default):
///   • hw.machine — sysctlbyname + uname (the model identifier).
///   • IDFV / IDFA — UIDevice.identifierForVendor + ASIdentifierManager.
///   • iOS version (only when the container sets one) — UIDevice.systemVersion,
///     NSProcessInfo.operatingSystemVersion(+String), sysctl kern.osproductversion
///     + kern.osversion, kept mutually consistent (version + real build number).
///
/// Deliberately NOT spoofed: hw.model board-id (unverified board IDs are a fresh
/// inconsistency tell) and UIScreen scale/bounds (mismatch would break layout on
/// the real panel). See IVDeviceIdentity.h — serial/model number are display-only.
///
/// Honest scope: this masks locally-readable identifiers only. Instagram binds
/// accounts to its OWN stored tokens (device_id, phone_id, X-MID, sessionid),
/// which are isolated by the HOME + keychain + CFPreferences redirects, not by
/// hardware spoofing.
@interface IVDeviceSpoof : NSObject

/// Install IDFV/IDFA swizzles + sysctl/uname C hooks (+ iOS-version surfaces when
/// the container sets one) for the given container. No-op for the default
/// container. Run once at launch.
+ (void)installForContainer:(IVContainer *)container;

/// The device model identifier this container presents (explicit override, or
/// the newest model in the real chip family when unset).
+ (NSString *)effectiveModelForContainer:(IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
