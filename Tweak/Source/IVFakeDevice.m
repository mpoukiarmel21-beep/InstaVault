#import "IVFakeDevice.h"

static NSArray *kModels() {
    return @[@"iPhone13,1",@"iPhone13,2",@"iPhone13,3",@"iPhone13,4",
             @"iPhone14,1",@"iPhone14,2",@"iPhone14,3",@"iPhone14,4",
             @"iPhone14,5",@"iPhone14,6",@"iPhone14,7",@"iPhone14,8",
             @"iPhone15,1",@"iPhone15,2",@"iPhone15,3",@"iPhone15,4",
             @"iPhone16,1",@"iPhone16,2"];
}
static NSArray *kNames() {
    return @[@"iPhone de Marie",@"iPhone de Pierre",@"iPhone de Sophie",
             @"iPhone de Lucas",@"iPhone de Chloé",@"iPhone de Thomas",
             @"iPhone de Léa",@"iPhone de Nicolas",@"iPhone de Camille",
             @"iPhone d'Antoine",@"iPhone de Julie",@"iPhone de Maxime",
             @"iPhone d'Emma",@"iPhone de Hugo",@"iPhone de Manon"];
}
static NSArray *kVersions() {
    return @[@"15.0",@"15.4",@"15.6",@"16.0",@"16.2",@"16.4",@"16.6",
             @"17.0",@"17.1",@"17.2",@"17.3",@"17.4",@"17.5"];
}

@implementation IVFakeDevice
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)generate { return [[self alloc] init]; }
- (instancetype)init {
    self = [super init];
    if (self) {
        _udid = [[NSUUID UUID] UUIDString];
        _idfv = [[NSUUID UUID] UUIDString];
        _idfa = [[NSUUID UUID] UUIDString];
        _serialNumber = [self mkSerial];
        _wifiMac = [self mkMAC];
        _btMac = [self mkMAC];
        _model = kModels()[arc4random_uniform((uint32_t)kModels().count)];
        _deviceName = kNames()[arc4random_uniform((uint32_t)kNames().count)];
        _osVersion = kVersions()[arc4random_uniform((uint32_t)kVersions().count)];
    }
    return self;
}
- (NSString *)mkSerial {
    static const char a[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *s = [NSMutableString stringWithString:@"F2L"];
    for (int i=0;i<9;i++) [s appendFormat:@"%c",a[arc4random_uniform(sizeof(a)-1)]];
    return s;
}
- (NSString *)mkMAC {
    NSMutableString *m = [NSMutableString string];
    for (int i=0;i<6;i++) { if(i)[m appendString:@":"]; [m appendFormat:@"%02X",arc4random_uniform(256)]; }
    return m;
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self=[super init]; if(self){
    _udid=[c decodeObjectOfClass:[NSString class] forKey:@"u"];
    _idfv=[c decodeObjectOfClass:[NSString class] forKey:@"v"];
    _idfa=[c decodeObjectOfClass:[NSString class] forKey:@"a"];
    _serialNumber=[c decodeObjectOfClass:[NSString class] forKey:@"s"];
    _wifiMac=[c decodeObjectOfClass:[NSString class] forKey:@"w"];
    _btMac=[c decodeObjectOfClass:[NSString class] forKey:@"b"];
    _model=[c decodeObjectOfClass:[NSString class] forKey:@"m"];
    _deviceName=[c decodeObjectOfClass:[NSString class] forKey:@"n"];
    _osVersion=[c decodeObjectOfClass:[NSString class] forKey:@"o"];
    } return self;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_udid forKey:@"u"];[c encodeObject:_idfv forKey:@"v"];
    [c encodeObject:_idfa forKey:@"a"];[c encodeObject:_serialNumber forKey:@"s"];
    [c encodeObject:_wifiMac forKey:@"w"];[c encodeObject:_btMac forKey:@"b"];
    [c encodeObject:_model forKey:@"m"];[c encodeObject:_deviceName forKey:@"n"];
    [c encodeObject:_osVersion forKey:@"o"];
}
- (NSDictionary *)toDict {
    return @{@"u":_udid,@"v":_idfv,@"a":_idfa,@"s":_serialNumber,
             @"w":_wifiMac,@"b":_btMac,@"m":_model,@"n":_deviceName,@"o":_osVersion};
}
- (instancetype)initWithDictionary:(NSDictionary *)d {
    self=[super init]; if(self){
    _udid=d[@"u"]?:[[NSUUID UUID] UUIDString];_idfv=d[@"v"]?:[[NSUUID UUID] UUIDString];
    _idfa=d[@"a"]?:[[NSUUID UUID] UUIDString];_serialNumber=d[@"s"]?:[self mkSerial];
    _wifiMac=d[@"w"]?:[self mkMAC];_btMac=d[@"b"]?:[self mkMAC];
    _model=d[@"m"]?:kModels()[0];_deviceName=d[@"n"]?:kNames()[0];_osVersion=d[@"o"]?:kVersions()[0];
    } return self;
}
@end
