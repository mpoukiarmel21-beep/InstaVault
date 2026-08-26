#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Per-container fake GPS (plan-directeur §6). Swizzles CLLocationManager and
/// the iOS 17+ CLLocationUpdate path so every location read/delivery returns a
/// freshly-synthesized CLLocation at the active container's coordinates.
///
/// Reads IVContainerStore.shared.activeContainer live on each delivery, so
/// editing the active container's coordinates takes effect without a restart.
/// When the active container has no location set, the real location flows through.
@interface IVLocationSpoof : NSObject

/// Install the CoreLocation hooks. Run once at launch (idempotent).
+ (void)install;

/// The coordinate currently being spoofed, or (kCLLocationCoordinate2DInvalid)
/// when spoofing is inactive. Reads the active container.
+ (BOOL)isActive;

@end

NS_ASSUME_NONNULL_END
