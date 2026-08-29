#import "IVContainer.h"
#import "IVFakeDevice.h"
#import "IVPaths.h"
#import <CoreLocation/CoreLocation.h>

static NSArray<NSString *> *IVRandomColors(void) {
    static NSArray *colors = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colors = @[@"#FF3B30",@"#FF9500",@"#FFCC00",@"#34C759",
                   @"#007AFF",@"#5856D6",@"#AF52DE",@"#FF2D55"];
    });
    return colors;
}

@implementation IVContainer

+ (BOOL)supportsSecureCoding { return YES; }

+ (instancetype)withName:(NSString *)n {
    IVContainer *c = [[self alloc] init];
    c.cid = [[NSUUID UUID] UUIDString];
    c.name = n;
    c.device = [IVFakeDevice generate];
    c.color = IVRandomColors()[arc4random_uniform((uint32_t)IVRandomColors().count)];
    c.created = [NSDate date];
    c.lastUsed = [NSDate date];
    c.active = NO;
    return c;
}

- (BOOL)hasLocation {
    return self.location.latitude != 0 || self.location.longitude != 0;
}

- (NSString *)sandbox {
    return [IVPaths containerRootForCID:self.cid];
}

- (NSString *)cookiePath {
    return [self.sandbox stringByAppendingPathComponent:@"Cookies"];
}

- (NSDictionary *)toDict {
    NSMutableDictionary *d = [NSMutableDictionary new];
    d[@"cid"] = self.cid ?: @"";
    d[@"name"] = self.name ?: @"";
    d[@"device"] = self.device.toDict ?: @{};
    d[@"locLat"] = @(self.location.latitude);
    d[@"locLon"] = @(self.location.longitude);
    d[@"locName"] = self.locName ?: @"";
    d[@"color"] = self.color ?: @"#007AFF";
    d[@"appLanguage"] = self.appLanguage ?: @"";
    d[@"regionCountry"] = self.regionCountry ?: @"";
    d[@"active"] = @(self.active);
    d[@"created"] = self.created ?: [NSDate date];
    d[@"lastUsed"] = self.lastUsed ?: [NSDate date];
    return [d copy];
}

- (instancetype)initWithDict:(NSDictionary *)d {
    self = [super init];
    if (self) {
        self.cid = d[@"cid"];
        self.name = d[@"name"];
        self.device = [[IVFakeDevice alloc] initWithDictionary:d[@"device"]];
        self.location = CLLocationCoordinate2DMake([d[@"locLat"] doubleValue], [d[@"locLon"] doubleValue]);
        self.locName = d[@"locName"];
        self.color = d[@"color"];
        self.appLanguage = d[@"appLanguage"];
        self.regionCountry = d[@"regionCountry"];
        self.active = [d[@"active"] boolValue];
        self.created = d[@"created"];
        self.lastUsed = d[@"lastUsed"];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        self.cid = [c decodeObjectOfClass:[NSString class] forKey:@"cid"];
        self.name = [c decodeObjectOfClass:[NSString class] forKey:@"name"];
        self.device = [c decodeObjectOfClass:[IVFakeDevice class] forKey:@"device"];
        self.location = CLLocationCoordinate2DMake([[c decodeObjectOfClass:[NSNumber class] forKey:@"lat"] doubleValue],
                                                    [[c decodeObjectOfClass:[NSNumber class] forKey:@"lon"] doubleValue]);
        self.locName = [c decodeObjectOfClass:[NSString class] forKey:@"locName"];
        self.color = [c decodeObjectOfClass:[NSString class] forKey:@"color"];
        self.appLanguage = [c decodeObjectOfClass:[NSString class] forKey:@"appLanguage"];
        self.regionCountry = [c decodeObjectOfClass:[NSString class] forKey:@"regionCountry"];
        self.active = [c decodeBoolForKey:@"active"];
        self.created = [c decodeObjectOfClass:[NSDate class] forKey:@"created"];
        self.lastUsed = [c decodeObjectOfClass:[NSDate class] forKey:@"lastUsed"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.cid forKey:@"cid"];
    [c encodeObject:self.name forKey:@"name"];
    [c encodeObject:self.device forKey:@"device"];
    [c encodeDouble:self.location.latitude forKey:@"lat"];
    [c encodeDouble:self.location.longitude forKey:@"lon"];
    [c encodeObject:self.locName forKey:@"locName"];
    [c encodeObject:self.color forKey:@"color"];
    [c encodeObject:self.appLanguage forKey:@"appLanguage"];
    [c encodeObject:self.regionCountry forKey:@"regionCountry"];
    [c encodeBool:self.active forKey:@"active"];
    [c encodeObject:self.created forKey:@"created"];
    [c encodeObject:self.lastUsed forKey:@"lastUsed"];
}

+ (NSString *)randomColor {
    return IVRandomColors()[arc4random_uniform((uint32_t)IVRandomColors().count)];
}

@end
