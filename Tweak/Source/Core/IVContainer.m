#import "IVContainer.h"

NSString *const kIVDefaultCID = @"default";

@implementation IVContainer

+ (instancetype)containerWithName:(NSString *)name {
    IVContainer *c = [IVContainer new];
    c.cid = [[NSUUID UUID] UUIDString];
    c.name = name.length ? name : @"Container";
    c.isDefault = NO;
    c.createdAt = [NSDate date];
    return c;
}

+ (instancetype)defaultContainer {
    IVContainer *c = [IVContainer new];
    c.cid = kIVDefaultCID;
    c.name = @"Principal";
    c.isDefault = YES;
    c.createdAt = [NSDate date];
    return c;
}

- (nullable instancetype)initWithDict:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *cid = dict[@"cid"];
    if (![cid isKindOfClass:[NSString class]] || cid.length == 0) return nil;

    if ((self = [super init])) {
        _cid = [cid copy];
        _name = [(dict[@"name"] ?: @"Container") copy];
        _isDefault = [dict[@"isDefault"] boolValue];
        _latitude = [dict[@"latitude"] isKindOfClass:[NSNumber class]] ? dict[@"latitude"] : nil;
        _longitude = [dict[@"longitude"] isKindOfClass:[NSNumber class]] ? dict[@"longitude"] : nil;
        _locationName = [dict[@"locationName"] isKindOfClass:[NSString class]] ? [dict[@"locationName"] copy] : nil;
        _deviceModel = [dict[@"deviceModel"] isKindOfClass:[NSString class]] ? [dict[@"deviceModel"] copy] : nil;
        _marketingName = [dict[@"marketingName"] isKindOfClass:[NSString class]] ? [dict[@"marketingName"] copy] : nil;
        _iosVersion = [dict[@"iosVersion"] isKindOfClass:[NSString class]] ? [dict[@"iosVersion"] copy] : nil;
        _appLanguage = [dict[@"appLanguage"] isKindOfClass:[NSString class]] ? [dict[@"appLanguage"] copy] : nil;
        _regionCountry = [dict[@"regionCountry"] isKindOfClass:[NSString class]] ? [dict[@"regionCountry"] copy] : nil;
        _createdAt = [dict[@"createdAt"] isKindOfClass:[NSDate class]] ? dict[@"createdAt"] : [NSDate date];
        _lastUsedAt = [dict[@"lastUsedAt"] isKindOfClass:[NSDate class]] ? dict[@"lastUsedAt"] : nil;
    }
    return self;
}

- (NSDictionary *)toDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"cid"] = self.cid ?: kIVDefaultCID;
    d[@"name"] = self.name ?: @"Container";
    d[@"isDefault"] = @(self.isDefault);
    if (self.latitude) d[@"latitude"] = self.latitude;
    if (self.longitude) d[@"longitude"] = self.longitude;
    if (self.locationName) d[@"locationName"] = self.locationName;
    if (self.deviceModel) d[@"deviceModel"] = self.deviceModel;
    if (self.marketingName) d[@"marketingName"] = self.marketingName;
    if (self.iosVersion) d[@"iosVersion"] = self.iosVersion;
    if (self.appLanguage) d[@"appLanguage"] = self.appLanguage;
    if (self.regionCountry) d[@"regionCountry"] = self.regionCountry;
    d[@"createdAt"] = self.createdAt ?: [NSDate date];
    if (self.lastUsedAt) d[@"lastUsedAt"] = self.lastUsedAt;
    return [d copy];
}

- (BOOL)hasLocation {
    return self.latitude != nil && self.longitude != nil;
}

@end
