#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IVDeviceFamily) {
    IVDeviceFamilyiPhone16ProMax,
    IVDeviceFamilyiPhone16Pro,
    IVDeviceFamilyiPhone16Plus,
    IVDeviceFamilyiPhone16,
    IVDeviceFamilyiPhone15ProMax,
    IVDeviceFamilyiPhone15Pro,
    IVDeviceFamilyiPhone15Plus,
    IVDeviceFamilyiPhone15,
    IVDeviceFamilyiPhone14ProMax,
    IVDeviceFamilyiPhone14Pro,
    IVDeviceFamilyiPhone14,
    IVDeviceFamilyiPhone13ProMax,
    IVDeviceFamilyiPhone13Pro,
    IVDeviceFamilyiPhone13,
    IVDeviceFamilyiPhone13Mini,
};

@interface IVFakeDevice : NSObject <NSCoding, NSSecureCoding>
@property (nonatomic, copy, readonly) NSString *udid;
@property (nonatomic, copy, readonly) NSString *idfv;
@property (nonatomic, copy, readonly) NSString *idfa;
@property (nonatomic, copy, readonly) NSString *serialNumber;
@property (nonatomic, copy, readonly) NSString *wifiMac;
@property (nonatomic, copy, readonly) NSString *btMac;
@property (nonatomic, copy, readonly) NSString *model;
@property (nonatomic, copy, readonly) NSString *modelName;
@property (nonatomic, copy, readonly) NSString *deviceName;
@property (nonatomic, copy, readonly) NSString *osVersion;
@property (nonatomic, copy, readonly) NSString *productType;
@property (nonatomic, copy, readonly) NSString *buildVersion;
@property (nonatomic, copy, readonly) NSString *hardwarePlatform;
@property (nonatomic, copy, readonly) NSString *cpuArchitecture;
@property (nonatomic, copy, readonly) NSString *totalDiskCapacity;
@property (nonatomic, copy, readonly) NSString *totalMemory;
@property (nonatomic, copy, readonly) NSString *screenWidth;
@property (nonatomic, copy, readonly) NSString *screenHeight;
@property (nonatomic, copy, readonly) NSString *screenScale;
@property (nonatomic, copy, readonly) NSString *batteryLevel;
@property (nonatomic, copy, readonly) NSString *batteryState;
@property (nonatomic, copy, readonly) NSString *carrierName;
@property (nonatomic, copy, readonly) NSString *airplaneMode;
@property (nonatomic, copy, readonly) NSString *hasPPP;
@property (nonatomic, copy, readonly) NSString *regionFormat;
@property (nonatomic, copy, readonly) NSString *timezone;
+ (instancetype)generate;
+ (NSArray<IVFakeDevice *> *)allModels;
- (NSDictionary *)toDict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)allMobileGestalt;
@end
