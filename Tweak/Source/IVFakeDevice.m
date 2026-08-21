#import "IVFakeDevice.h"

typedef struct {
    const char *model;
    const char *modelName;
    const char *productType;
    const char *hardwarePlatform;
    const char *cpuArchitecture;
    int screenWidth;
    int screenHeight;
    double screenScale;
} IVDeviceSpec;

static const IVDeviceSpec kSpecs[] = {
    {"iPhone16,2", "iPhone 16 Pro Max", "iPhone16,2", "s5l8920x", "arm64e", 440, 932, 3.0},
    {"iPhone16,1", "iPhone 16 Pro",     "iPhone16,1", "s5l8920x", "arm64e", 393, 852, 3.0},
    {"iPhone15,4", "iPhone 16 Plus",    "iPhone15,4", "s5l8910x", "arm64e", 430, 932, 3.0},
    {"iPhone15,3", "iPhone 16",         "iPhone15,3", "s5l8910x", "arm64e", 393, 852, 3.0},
    {"iPhone15,2", "iPhone 15 Pro Max", "iPhone15,2", "s5l8910x", "arm64e", 430, 932, 3.0},
    {"iPhone15,1", "iPhone 15 Pro",     "iPhone15,1", "s5l8910x", "arm64e", 393, 852, 3.0},
    {"iPhone14,8", "iPhone 15 Plus",    "iPhone14,8", "s5l8900x", "arm64e", 430, 932, 3.0},
    {"iPhone14,7", "iPhone 15",         "iPhone14,7", "s5l8900x", "arm64e", 393, 852, 3.0},
    {"iPhone14,6", "iPhone 14 Pro Max", "iPhone14,6", "s5l8900x", "arm64e", 430, 932, 3.0},
    {"iPhone14,5", "iPhone 14 Pro",     "iPhone14,5", "s5l8900x", "arm64e", 393, 852, 3.0},
};

static NSArray<NSNumber *> *kSpecIndices(void) {
    static NSMutableArray *a;
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        a = [NSMutableArray new];
        for (int i = 0; i < (int)(sizeof(kSpecs)/sizeof(kSpecs[0])); i++) [a addObject:@(i)];
    });
    return a;
}

static NSArray<NSString *> *kOSVersions(void) {
    return @[@"26.6.1",@"26.6",@"26.5.1",@"26.5",@"26.4.1",@"26.4",
             @"26.3.1",@"26.3",@"26.2",@"26.1.1",@"26.1",
             @"18.7.1",@"18.7",@"18.6.1",@"18.6",@"18.5.1"];
}

static NSArray<NSString *> *kBuilds(void) {
    return @[@"23G93",@"23G90",@"23G80",@"23G70",@"23G60",
             @"22H220",@"22H212",@"22H190",@"22H180",
             @"22F80",@"22F70",@"22F66"];
}

static NSArray<NSString *> *kCarrierNames(void) {
    return @[@"T-Mobile",@"AT&T",@"Verizon",@"Vodafone FR",@"Orange FR",
             @"SFR",@"Bouygues Telecom",@"MEO",@"O2",@"EE",
             @"Rogers",@"Telus",@"Optus",@"SoftBank",@"KDDI"];
}

static NSArray<NSString *> *kDeviceNames(void) {
    return @[@"iPhone",@"Mon iPhone",@"Le device"];
}

static NSArray<NSString *> *kRegionFormats(void) {
    return @[@"FR_fr",@"US_en",@"GB_en",@"DE_de",@"ES_es",
             @"IT_it",@"PT_pt",@"JP_ja",@"BR_pt",@"CA_en"];
}

static NSArray<NSString *> *kTimezones(void) {
    return @[@"Europe/Paris",@"Europe/London",@"America/New_York",
             @"America/Los_Angeles",@"Asia/Tokyo",@"Europe/Berlin",
             @"America/Chicago",@"Europe/Madrid",@"Asia/Dubai",
             @"Australia/Sydney"];
}

static NSString *RandFrom(NSArray *a) {
    return a[arc4random_uniform((uint32_t)a.count)];
}

static NSString *RandMAC(void) {
    static const char h[] = "0123456789ABCDEF";
    NSMutableString *m = [NSMutableString new];
    for (int i = 0; i < 6; i++) {
        if (i) [m appendString:@":"];
        [m appendFormat:@"%c%c", h[arc4random_uniform(16)], h[arc4random_uniform(16)]];
    }
    return [m copy];
}

static NSString *RandSerial(void) {
    static const char c[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    NSMutableString *s = [NSMutableString stringWithString:@"F2L"];
    for (int i = 0; i < 8; i++) [s appendFormat:@"%c", c[arc4random_uniform(sizeof(c)-1)]];
    return [s copy];
}

@implementation IVFakeDevice

+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)generate { return [[self alloc] init]; }

+ (NSArray<IVFakeDevice *> *)allModels {
    static NSArray *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *arr = [NSMutableArray new];
        for (int i = 0; i < (int)(sizeof(kSpecs)/sizeof(kSpecs[0])); i++) {
            IVFakeDevice *d = [[IVFakeDevice alloc] init];
            d->_model = [NSString stringWithUTF8String:kSpecs[i].model];
            d->_modelName = [NSString stringWithUTF8String:kSpecs[i].modelName];
            d->_productType = [NSString stringWithUTF8String:kSpecs[i].productType];
            d->_hardwarePlatform = [NSString stringWithUTF8String:kSpecs[i].hardwarePlatform];
            d->_cpuArchitecture = [NSString stringWithUTF8String:kSpecs[i].cpuArchitecture];
            d->_screenWidth = [NSString stringWithFormat:@"%d", kSpecs[i].screenWidth];
            d->_screenHeight = [NSString stringWithFormat:@"%d", kSpecs[i].screenHeight];
            d->_screenScale = [NSString stringWithFormat:@"%.1f", kSpecs[i].screenScale];
            [arr addObject:d];
        }
        cached = [arr copy];
    });
    return cached;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *indices = kSpecIndices();
        NSUInteger idx = arc4random_uniform((uint32_t)indices.count);
        NSUInteger specIdx = [(NSNumber *)indices[idx] unsignedIntegerValue];
        const IVDeviceSpec *spec = &kSpecs[specIdx];

        _udid = [[[NSUUID UUID] UUIDString] uppercaseString];
        _idfv = [[[NSUUID UUID] UUIDString] uppercaseString];
        _idfa = [[[NSUUID UUID] UUIDString] uppercaseString];
        _serialNumber = RandSerial();
        _wifiMac = RandMAC();
        _btMac = RandMAC();
        _model = [NSString stringWithUTF8String:spec->model];
        _modelName = [NSString stringWithUTF8String:spec->modelName];
        _productType = [NSString stringWithUTF8String:spec->productType];
        _hardwarePlatform = [NSString stringWithUTF8String:spec->hardwarePlatform];
        _cpuArchitecture = [NSString stringWithUTF8String:spec->cpuArchitecture];
        _screenWidth = [NSString stringWithFormat:@"%d", spec->screenWidth];
        _screenHeight = [NSString stringWithFormat:@"%d", spec->screenHeight];
        _screenScale = [NSString stringWithFormat:@"%.1f", spec->screenScale];
        _deviceName = RandFrom(kDeviceNames());
        _osVersion = RandFrom(kOSVersions());
        _buildVersion = RandFrom(kBuilds());
        _batteryLevel = [NSString stringWithFormat:@"%d", 40 + arc4random_uniform(51)];
        _batteryState = @"2";
        _carrierName = RandFrom(kCarrierNames());
        _airplaneMode = @"0";
        _hasPPP = @"1";
        _regionFormat = RandFrom(kRegionFormats());
        _timezone = RandFrom(kTimezones());
    }
    return self;
}

- (NSDictionary *)allMobileGestalt {
    return @{
        @"UniqueDeviceID": _udid ?: @"",
        @"SerialNumber": _serialNumber ?: @"",
        @"ProductType": _productType ?: @"",
        @"ModelNumber": [NSString stringWithFormat:@"%@, %@", _model ?: @"", _serialNumber ?: @""],
        @"HWModelStr": _model ?: @"",
        @"DeviceName": _deviceName ?: @"",
        @"ProductVersion": _osVersion ?: @"",
        @"BuildVersion": _buildVersion ?: @"",
        @"HardwarePlatform": _hardwarePlatform ?: @"",
        @"CPUArchitecture": _cpuArchitecture ?: @"",
        @"TotalDiskCapacity": @"256000000000",
        @"TotalMemory": @"8589934592",
        @"DeviceClass": @"iPhone",
        @"DeviceColor": @"1, 1, 1",
        @"DeviceEnclosureColor": @"0.286275, 0.286275, 0.301961",
        @"HasBaseband": @"1",
        @"BasebandFirmwareVersion": @"3.52.01",
        @"BasebandSerialNumber": @"6.51.00",
        @"BasebandChipId": @"8960",
        @"TelephonyCapability": @"1",
        @"AirplaneMode": _airplaneMode ?: @"0",
        @"AllowYouTube": @"1",
        @"AllowYouTubePlugin": @"1",
        @"MinimumSupportediTunesVersion": @"12.12",
        @"ProximitySensorCalibration": @"1035727114",
        @"BatteryCurrentCapacity": _batteryLevel ?: @"50",
        @"BatteryIsCharging": @"0",
        @"BatteryIsFullyCharged": @"0",
        @"ExternalPowerSourceState": @"0",
        @"IsSimulator": @"0",
        @"PasswordConfigured": @"1",
        @"PasswordProtected": @"1",
        @"ActiveWirelessTechnology": @"1",
        @"CompassCalibration": @"1038.773071, -61.668098, -65.434837",
        @"BasebandSecurityInfoBlob": @"5.39.01",
        @"FirmwareVersion": @"6723.120.1",
        @"PartitionType": @"GUID_partition_scheme",
        @"FDRSealingStatus": @"0",
        @"AirplaneModeWiFi": @"0",
        @"WifiAddress": _wifiMac ?: @"",
        @"BluetoothAddress": _btMac ?: @"",
    };
}

- (NSDictionary *)toDict {
    return @{
        @"udid": _udid ?: @"",
        @"idfv": _idfv ?: @"",
        @"idfa": _idfa ?: @"",
        @"serial": _serialNumber ?: @"",
        @"wifiMac": _wifiMac ?: @"",
        @"btMac": _btMac ?: @"",
        @"model": _model ?: @"",
        @"modelName": _modelName ?: @"",
        @"deviceName": _deviceName ?: @"",
        @"osVersion": _osVersion ?: @"",
        @"productType": _productType ?: @"",
        @"buildVersion": _buildVersion ?: @"",
        @"hwPlatform": _hardwarePlatform ?: @"",
        @"cpuArch": _cpuArchitecture ?: @"",
        @"totalDisk": _totalDiskCapacity ?: @"",
        @"totalMem": _totalMemory ?: @"",
        @"scrW": _screenWidth ?: @"",
        @"scrH": _screenHeight ?: @"",
        @"scrS": _screenScale ?: @"",
        @"battLevel": _batteryLevel ?: @"",
        @"battState": _batteryState ?: @"",
        @"carrier": _carrierName ?: @"",
        @"airplane": _airplaneMode ?: @"",
        @"hasPPP": _hasPPP ?: @"",
        @"region": _regionFormat ?: @"",
        @"tz": _timezone ?: @"",
    };
}

- (instancetype)initWithDictionary:(NSDictionary *)d {
    self = [super init];
    if (self) {
        _udid = d[@"udid"] ?: [[[NSUUID UUID] UUIDString] uppercaseString];
        _idfv = d[@"idfv"] ?: [[[NSUUID UUID] UUIDString] uppercaseString];
        _idfa = d[@"idfa"] ?: [[[NSUUID UUID] UUIDString] uppercaseString];
        _serialNumber = d[@"serial"] ?: RandSerial();
        _wifiMac = d[@"wifiMac"] ?: RandMAC();
        _btMac = d[@"btMac"] ?: RandMAC();
        _model = d[@"model"] ?: @"iPhone16,2";
        _modelName = d[@"modelName"] ?: @"iPhone 16 Pro Max";
        _deviceName = d[@"deviceName"] ?: RandFrom(kDeviceNames());
        _osVersion = d[@"osVersion"] ?: @"26.6.1";
        _productType = d[@"productType"] ?: _model;
        _buildVersion = d[@"buildVersion"] ?: @"23G93";
        _hardwarePlatform = d[@"hwPlatform"] ?: @"s5l8920x";
        _cpuArchitecture = d[@"cpuArch"] ?: @"arm64e";
        _totalDiskCapacity = d[@"totalDisk"] ?: @"256000000000";
        _totalMemory = d[@"totalMem"] ?: @"8589934592";
        _screenWidth = d[@"scrW"] ?: @"440";
        _screenHeight = d[@"scrH"] ?: @"932";
        _screenScale = d[@"scrS"] ?: @"3.0";
        _batteryLevel = d[@"battLevel"] ?: @"73";
        _batteryState = d[@"battState"] ?: @"2";
        _carrierName = d[@"carrier"] ?: RandFrom(kCarrierNames());
        _airplaneMode = d[@"airplane"] ?: @"0";
        _hasPPP = d[@"hasPPP"] ?: @"1";
        _regionFormat = d[@"region"] ?: RandFrom(kRegionFormats());
        _timezone = d[@"tz"] ?: RandFrom(kTimezones());
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _udid = [c decodeObjectOfClass:[NSString class] forKey:@"udid"];
        _idfv = [c decodeObjectOfClass:[NSString class] forKey:@"idfv"];
        _idfa = [c decodeObjectOfClass:[NSString class] forKey:@"idfa"];
        _serialNumber = [c decodeObjectOfClass:[NSString class] forKey:@"serial"];
        _wifiMac = [c decodeObjectOfClass:[NSString class] forKey:@"wifi"];
        _btMac = [c decodeObjectOfClass:[NSString class] forKey:@"bt"];
        _model = [c decodeObjectOfClass:[NSString class] forKey:@"model"];
        _modelName = [c decodeObjectOfClass:[NSString class] forKey:@"modelName"];
        _deviceName = [c decodeObjectOfClass:[NSString class] forKey:@"devName"];
        _osVersion = [c decodeObjectOfClass:[NSString class] forKey:@"osVer"];
        _productType = [c decodeObjectOfClass:[NSString class] forKey:@"prodType"];
        _buildVersion = [c decodeObjectOfClass:[NSString class] forKey:@"build"];
        _hardwarePlatform = [c decodeObjectOfClass:[NSString class] forKey:@"hwPlat"];
        _cpuArchitecture = [c decodeObjectOfClass:[NSString class] forKey:@"cpuArch"];
        _totalDiskCapacity = [c decodeObjectOfClass:[NSString class] forKey:@"disk"];
        _totalMemory = [c decodeObjectOfClass:[NSString class] forKey:@"mem"];
        _screenWidth = [c decodeObjectOfClass:[NSString class] forKey:@"scrW"];
        _screenHeight = [c decodeObjectOfClass:[NSString class] forKey:@"scrH"];
        _screenScale = [c decodeObjectOfClass:[NSString class] forKey:@"scrS"];
        _batteryLevel = [c decodeObjectOfClass:[NSString class] forKey:@"batt"];
        _batteryState = [c decodeObjectOfClass:[NSString class] forKey:@"battSt"];
        _carrierName = [c decodeObjectOfClass:[NSString class] forKey:@"carrier"];
        _airplaneMode = [c decodeObjectOfClass:[NSString class] forKey:@"air"];
        _hasPPP = [c decodeObjectOfClass:[NSString class] forKey:@"ppp"];
        _regionFormat = [c decodeObjectOfClass:[NSString class] forKey:@"region"];
        _timezone = [c decodeObjectOfClass:[NSString class] forKey:@"tz"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_udid forKey:@"udid"];
    [c encodeObject:_idfv forKey:@"idfv"];
    [c encodeObject:_idfa forKey:@"idfa"];
    [c encodeObject:_serialNumber forKey:@"serial"];
    [c encodeObject:_wifiMac forKey:@"wifi"];
    [c encodeObject:_btMac forKey:@"bt"];
    [c encodeObject:_model forKey:@"model"];
    [c encodeObject:_modelName forKey:@"modelName"];
    [c encodeObject:_deviceName forKey:@"devName"];
    [c encodeObject:_osVersion forKey:@"osVer"];
    [c encodeObject:_productType forKey:@"prodType"];
    [c encodeObject:_buildVersion forKey:@"build"];
    [c encodeObject:_hardwarePlatform forKey:@"hwPlat"];
    [c encodeObject:_cpuArchitecture forKey:@"cpuArch"];
    [c encodeObject:_totalDiskCapacity forKey:@"disk"];
    [c encodeObject:_totalMemory forKey:@"mem"];
    [c encodeObject:_screenWidth forKey:@"scrW"];
    [c encodeObject:_screenHeight forKey:@"scrH"];
    [c encodeObject:_screenScale forKey:@"scrS"];
    [c encodeObject:_batteryLevel forKey:@"batt"];
    [c encodeObject:_batteryState forKey:@"battSt"];
    [c encodeObject:_carrierName forKey:@"carrier"];
    [c encodeObject:_airplaneMode forKey:@"air"];
    [c encodeObject:_hasPPP forKey:@"ppp"];
    [c encodeObject:_regionFormat forKey:@"region"];
    [c encodeObject:_timezone forKey:@"tz"];
}

@end
