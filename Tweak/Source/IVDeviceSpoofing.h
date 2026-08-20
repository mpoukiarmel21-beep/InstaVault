#import <Foundation/Foundation.h>
@class IVFakeDevice;
@interface IVDeviceSpoofing : NSObject
@property (nonatomic, assign) BOOL on;
@property (nonatomic, strong) IVFakeDevice *dev;
+ (instancetype)shared;
- (void)enable:(IVFakeDevice *)d;
- (void)disable;
- (NSString *)udid;
- (NSString *)idfv;
- (NSString *)idfa;
- (NSString *)serial;
- (NSString *)wifi;
- (NSString *)bt;
- (NSString *)model;
- (NSString *)name;
- (NSString *)os;
@end
