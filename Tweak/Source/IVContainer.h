#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
@class IVFakeDevice;

@interface IVContainer : NSObject <NSCoding, NSSecureCoding>
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) IVFakeDevice *device;
@property (nonatomic, assign) CLLocationCoordinate2D location;
@property (nonatomic, copy) NSString *locName;
@property (nonatomic, copy) NSString *color;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, strong) NSDate *created;
@property (nonatomic, strong) NSDate *lastUsed;
+ (instancetype)withName:(NSString *)n;
+ (NSString *)randomColor;
- (NSDictionary *)toDict;
- (instancetype)initWithDict:(NSDictionary *)d;
- (BOOL)hasLocation;
- (NSString *)sandbox;
- (NSString *)cookiePath;
@end
