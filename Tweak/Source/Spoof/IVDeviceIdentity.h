#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One real iPhone the app can present itself as. Grouped by EXACT SoC
/// (`chipFamily`) so a container may only masquerade as a device sharing the
/// physical device's chip generation — an iPhone 11 (A13) can never claim to be
/// an iPhone 17 (A19). See plan-directeur §7 and docs/audit v2 blueprint §2.2.
@interface IVDeviceModel : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;     // "iPhone17,1"
@property (nonatomic, copy, readonly) NSString *marketingName;  // "iPhone 16 Pro"
@property (nonatomic, copy, readonly) NSString *chipFamily;     // "A18 Pro"
@end

/// The device-identity source of truth: the full model matrix, the real-chip
/// detection used to constrain the picker, the selectable iOS versions (with
/// their real build numbers, needed to keep kern.osproductversion and
/// kern.osversion internally consistent), and the deterministic DISPLAY-ONLY
/// serial / model number.
///
/// Serial and model number are display-only ON PURPOSE: a sandboxed app on
/// iOS 26 cannot read the real serial / MobileGestalt region, so Instagram
/// never asks for them through a channel we could answer. Emitting a fabricated
/// value where the OS returns nothing would be a fresh tell — so these are shown
/// in the info sheet for the user, never fed to a hook.
@interface IVDeviceIdentity : NSObject

/// Capture the REAL device chip family. MUST be called from the constructor
/// BEFORE IVDeviceSpoof installs its sysctl/uname hooks, otherwise the read
/// would return the spoofed model. Idempotent.
+ (void)captureRealChip;

/// The real device's chip family (e.g. "A13 Bionic"). Lazily captures if
/// +captureRealChip was somehow not called first.
+ (NSString *)realChipFamily;

/// Every known model, newest first.
+ (NSArray<IVDeviceModel *> *)allModels;

/// Models sharing the real device's chip family — what this device may present
/// as — newest first. Never empty (falls back to the real model itself).
+ (NSArray<IVDeviceModel *> *)modelsForRealChip;

/// The model a brand-new container should default to: the newest model in the
/// real chip family.
+ (IVDeviceModel *)defaultModel;

+ (nullable IVDeviceModel *)modelForIdentifier:(NSString *)identifier;

/// Marketing name for an identifier; falls back to the identifier itself.
+ (NSString *)marketingNameForIdentifier:(nullable NSString *)identifier;

/// Selectable iOS marketing versions, newest first (e.g. "26.6.1").
+ (NSArray<NSString *> *)iosVersions;

/// The real build string (kern.osversion) for an iOS version, e.g. "23G83".
+ (nullable NSString *)buildForIOSVersion:(NSString *)version;

/// Deterministic display-only serial (10 chars) for a container.
+ (NSString *)serialForCID:(NSString *)cid;

/// Deterministic display-only model number for a container, e.g. "MG2K3FD/A".
/// The region suffix follows `region` (ISO code) when known.
+ (NSString *)modelNumberForCID:(NSString *)cid region:(nullable NSString *)region;

@end

NS_ASSUME_NONNULL_END
