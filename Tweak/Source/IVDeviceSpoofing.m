#import "IVDeviceSpoofing.h"
#import "IVFakeDevice.h"
@implementation IVDeviceSpoofing
+ (instancetype)shared { static IVDeviceSpoofing *i; static dispatch_once_t o; dispatch_once(&o, ^{ i=[self new]; }); return i; }
- (void)enable:(IVFakeDevice *)d { self.dev=d; self.on=YES; }
- (void)disable { self.dev=nil; self.on=NO; }
- (NSString *)udid { return self.on?self.dev.udid:nil; }
- (NSString *)idfv { return self.on?self.dev.idfv:nil; }
- (NSString *)idfa { return self.on?self.dev.idfa:nil; }
- (NSString *)serial { return self.on?self.dev.serialNumber:nil; }
- (NSString *)wifi { return self.on?self.dev.wifiMac:nil; }
- (NSString *)bt { return self.on?self.dev.btMac:nil; }
- (NSString *)model { return self.on?self.dev.model:nil; }
- (NSString *)name { return self.on?self.dev.deviceName:nil; }
- (NSString *)os { return self.on?self.dev.osVersion:nil; }
@end
