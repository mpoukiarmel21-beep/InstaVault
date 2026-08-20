#import <Foundation/Foundation.h>

@interface IVFakeDevice : NSObject <NSCoding, NSSecureCoding>
@property (nonatomic, copy, readonly) NSString *udid;
@property (nonatomic, copy, readonly) NSString *idfv;
@property (nonatomic, copy, readonly) NSString *idfa;
@property (nonatomic, copy, readonly) NSString *serialNumber;
@property (nonatomic, copy, readonly) NSString *wifiMac;
@property (nonatomic, copy, readonly) NSString *btMac;
@property (nonatomic, copy, readonly) NSString *model;
@property (nonatomic, copy, readonly) NSString *deviceName;
@property (nonatomic, copy, readonly) NSString *osVersion;
+ (instancetype)generate;
- (NSDictionary *)toDict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end
