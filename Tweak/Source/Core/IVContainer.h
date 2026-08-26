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
/// deterministically from the container seed (SHA256(cid)).
@property (nonatomic, copy, nullable) NSString *deviceModel;

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
