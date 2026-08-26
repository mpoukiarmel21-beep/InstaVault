#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A single isolated container ("a phone" from Instagram's point of view).
/// Persisted as a plist dictionary (NSPropertyListSerialization), never
/// NSKeyedArchiver (which caused a nil crash in v1).
@interface IVContainer : NSObject

/// Stable unique id. The default container uses the constant kIVDefaultCID.
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSString *name;

/// YES for the one non-deletable, non-renamable default container. The default
/// container is NOT redirected (HOME stays real) so existing logins survive.
@property (nonatomic, assign) BOOL isDefault;

/// Fake GPS. nil latitude/longitude == no location spoofing for this container.
@property (nonatomic, strong, nullable) NSNumber *latitude;
@property (nonatomic, strong, nullable) NSNumber *longitude;
@property (nonatomic, copy, nullable) NSString *locationName;   // "City, Country"

/// Spoofed device model identifier, e.g. "iPhone14,2". nil == derive
/// deterministically (newest model in the REAL chip family). This is the
/// canonical identifier fed to the sysctl/uname hooks.
@property (nonatomic, copy, nullable) NSString *deviceModel;

/// Human marketing name for `deviceModel`, e.g. "iPhone 16 Pro". Persisted for
/// stable display; recomputable from deviceModel via IVDeviceIdentity.
@property (nonatomic, copy, nullable) NSString *marketingName;

/// Spoofed iOS marketing version, e.g. "26.6.1". nil == report the real OS
/// version unchanged. When set it is answered on every OS-version surface
/// (UIDevice.systemVersion, NSProcessInfo, sysctl kern.osproductversion/osversion).
@property (nonatomic, copy, nullable) NSString *iosVersion;

/// App language override (ISO code, e.g. "fr", "en"). nil == no override.
@property (nonatomic, copy, nullable) NSString *appLanguage;

/// Region/country reference (ISO code, e.g. "FR", "US"). Drives NSLocale /
/// NSTimeZone spoofing + the display-only model number suffix. nil == no override.
@property (nonatomic, copy, nullable) NSString *regionCountry;

@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *lastUsedAt;

+ (instancetype)containerWithName:(NSString *)name;
+ (instancetype)defaultContainer;

- (nullable instancetype)initWithDict:(NSDictionary *)dict;
- (NSDictionary *)toDict;

- (BOOL)hasLocation;

@end

/// The default container's fixed id.
extern NSString *const kIVDefaultCID;

NS_ASSUME_NONNULL_END
