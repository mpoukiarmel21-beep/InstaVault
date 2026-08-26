#import "IVDeviceIdentity.h"
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>

#pragma mark - IVDeviceModel

@interface IVDeviceModel ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *marketingName;
@property (nonatomic, copy, readwrite) NSString *chipFamily;
@end

@implementation IVDeviceModel
+ (instancetype)id:(NSString *)identifier name:(NSString *)name chip:(NSString *)chip {
    IVDeviceModel *m = [IVDeviceModel new];
    m.identifier = identifier; m.marketingName = name; m.chipFamily = chip;
    return m;
}
@end

#pragma mark - State

static NSString *gRealIdentifier = nil;   // real hw.machine, captured pre-hook
static NSString *gRealChipFamily = nil;   // chip family of the real device

// A-to-Z/0-9 charset without the ambiguous I/O, for deterministic id strings.
static NSString *const kIVSerialCharset = @"0123456789ABCDEFGHJKLMNPQRSTUVWXYZ";

#pragma mark - Matrix

// The full iPhone matrix, newest first, grouped by EXACT SoC. Identifiers and
// marketing names verified against Apple's line-up through the iPhone 17 family
// (Sept 2025) + iPhone 16e / 17e. Extend the head as new models ship.
static NSArray<IVDeviceModel *> *IVBuildMatrix(void) {
    return @[
        [IVDeviceModel id:@"iPhone18,2" name:@"iPhone 17 Pro Max" chip:@"A19 Pro"],
        [IVDeviceModel id:@"iPhone18,1" name:@"iPhone 17 Pro"     chip:@"A19 Pro"],
        [IVDeviceModel id:@"iPhone18,4" name:@"iPhone Air"        chip:@"A19 Pro"],
        [IVDeviceModel id:@"iPhone18,3" name:@"iPhone 17"         chip:@"A19"],
        [IVDeviceModel id:@"iPhone18,5" name:@"iPhone 17e"        chip:@"A19"],
        [IVDeviceModel id:@"iPhone17,2" name:@"iPhone 16 Pro Max" chip:@"A18 Pro"],
        [IVDeviceModel id:@"iPhone17,1" name:@"iPhone 16 Pro"     chip:@"A18 Pro"],
        [IVDeviceModel id:@"iPhone17,4" name:@"iPhone 16 Plus"    chip:@"A18"],
        [IVDeviceModel id:@"iPhone17,3" name:@"iPhone 16"         chip:@"A18"],
        [IVDeviceModel id:@"iPhone17,5" name:@"iPhone 16e"        chip:@"A18"],
        [IVDeviceModel id:@"iPhone16,2" name:@"iPhone 15 Pro Max" chip:@"A17 Pro"],
        [IVDeviceModel id:@"iPhone16,1" name:@"iPhone 15 Pro"     chip:@"A17 Pro"],
        [IVDeviceModel id:@"iPhone15,5" name:@"iPhone 15 Plus"    chip:@"A16 Bionic"],
        [IVDeviceModel id:@"iPhone15,4" name:@"iPhone 15"         chip:@"A16 Bionic"],
        [IVDeviceModel id:@"iPhone15,3" name:@"iPhone 14 Pro Max" chip:@"A16 Bionic"],
        [IVDeviceModel id:@"iPhone15,2" name:@"iPhone 14 Pro"     chip:@"A16 Bionic"],
        [IVDeviceModel id:@"iPhone14,8" name:@"iPhone 14 Plus"    chip:@"A15 (5-core)"],
        [IVDeviceModel id:@"iPhone14,7" name:@"iPhone 14"         chip:@"A15 (5-core)"],
        [IVDeviceModel id:@"iPhone14,3" name:@"iPhone 13 Pro Max" chip:@"A15 (5-core)"],
        [IVDeviceModel id:@"iPhone14,2" name:@"iPhone 13 Pro"     chip:@"A15 (5-core)"],
        [IVDeviceModel id:@"iPhone14,5" name:@"iPhone 13"         chip:@"A15 (4-core)"],
        [IVDeviceModel id:@"iPhone14,4" name:@"iPhone 13 mini"    chip:@"A15 (4-core)"],
        [IVDeviceModel id:@"iPhone13,4" name:@"iPhone 12 Pro Max" chip:@"A14 Bionic"],
        [IVDeviceModel id:@"iPhone13,3" name:@"iPhone 12 Pro"     chip:@"A14 Bionic"],
        [IVDeviceModel id:@"iPhone13,2" name:@"iPhone 12"         chip:@"A14 Bionic"],
        [IVDeviceModel id:@"iPhone13,1" name:@"iPhone 12 mini"    chip:@"A14 Bionic"],
        [IVDeviceModel id:@"iPhone12,5" name:@"iPhone 11 Pro Max" chip:@"A13 Bionic"],
        [IVDeviceModel id:@"iPhone12,3" name:@"iPhone 11 Pro"     chip:@"A13 Bionic"],
        [IVDeviceModel id:@"iPhone12,1" name:@"iPhone 11"         chip:@"A13 Bionic"],
    ];
}

#pragma mark - IVDeviceIdentity

@implementation IVDeviceIdentity

+ (NSArray<IVDeviceModel *> *)allModels {
    static NSArray<IVDeviceModel *> *models = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ models = IVBuildMatrix(); });
    return models;
}

+ (void)captureRealChip {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char buf[256] = {0};
        size_t len = sizeof(buf);
        // Read hw.machine directly — this runs BEFORE IVDeviceSpoof rebinds
        // sysctlbyname, so it returns the genuine hardware identifier.
        if (sysctlbyname("hw.machine", buf, &len, NULL, 0) == 0 && buf[0]) {
            gRealIdentifier = [NSString stringWithUTF8String:buf];
        }
        IVDeviceModel *m = [self modelForIdentifier:gRealIdentifier];
        gRealChipFamily = m ? m.chipFamily : (gRealIdentifier ?: @"unknown");
    });
}

+ (NSString *)realChipFamily {
    if (!gRealChipFamily) [self captureRealChip];
    return gRealChipFamily ?: @"unknown";
}

+ (IVDeviceModel *)modelForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) return nil;
    for (IVDeviceModel *m in [self allModels]) {
        if ([m.identifier isEqualToString:identifier]) return m;
    }
    return nil;
}

+ (NSString *)marketingNameForIdentifier:(NSString *)identifier {
    IVDeviceModel *m = [self modelForIdentifier:identifier];
    return m ? m.marketingName : (identifier ?: @"Appareil");
}

+ (NSArray<IVDeviceModel *> *)modelsForRealChip {
    NSString *family = [self realChipFamily];
    NSMutableArray<IVDeviceModel *> *out = [NSMutableArray new];
    for (IVDeviceModel *m in [self allModels]) {
        if ([m.chipFamily isEqualToString:family]) [out addObject:m];
    }
    if (out.count == 0) {
        // Real device not in the matrix (newer than we know). Do NOT let it
        // masquerade as anything — offer only its own identity.
        NSString *ident = gRealIdentifier ?: @"iPhone";
        [out addObject:[IVDeviceModel id:ident
                                    name:[self marketingNameForIdentifier:ident]
                                    chip:family]];
    }
    return [out copy];
}

+ (IVDeviceModel *)defaultModel {
    return [self modelsForRealChip].firstObject;
}

#pragma mark - iOS versions (marketing version -> real build)

+ (NSArray<NSString *> *)iosVersions {
    return @[ @"26.6.1", @"26.6", @"26.5", @"26.4", @"26.3", @"26.2", @"26.1", @"26.0.1", @"26.0" ];
}

+ (NSString *)buildForIOSVersion:(NSString *)version {
    static NSDictionary<NSString *, NSString *> *builds = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        builds = @{
            @"26.6.1": @"23G83", @"26.6": @"23G71", @"26.5": @"23F84",
            @"26.4":   @"23E261", @"26.3": @"23D812", @"26.2": @"23C71",
            @"26.1":   @"23B85",  @"26.0.1": @"23A355", @"26.0": @"23A340",
        };
    });
    return builds[version ?: @""];
}

#pragma mark - Display-only serial / model number (deterministic per cid)

// 32-byte SHA256 of (cid|tag) — stable across launches, unique per container.
static void IVIdentitySeed(NSString *cid, NSString *tag, unsigned char out[CC_SHA256_DIGEST_LENGTH]) {
    NSString *s = [NSString stringWithFormat:@"%@|%@", cid ?: @"", tag];
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(d.bytes, (CC_LONG)d.length, out);
}

static NSString *IVCharsFromSeed(const unsigned char *h, NSUInteger count, NSUInteger offset) {
    NSUInteger n = kIVSerialCharset.length;
    NSMutableString *s = [NSMutableString stringWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        unsigned char b = h[(offset + i) % CC_SHA256_DIGEST_LENGTH];
        [s appendFormat:@"%C", [kIVSerialCharset characterAtIndex:(b % n)]];
    }
    return s;
}

+ (NSString *)serialForCID:(NSString *)cid {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    IVIdentitySeed(cid, @"serial", h);
    return IVCharsFromSeed(h, 10, 0);   // modern Apple serials are 10 chars
}

// Region -> the 1-2 char suffix Apple uses in a model number (…F/A = France).
static NSString *IVRegionSuffix(NSString *region) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"US": @"LL", @"FR": @"F", @"GB": @"B", @"DE": @"D", @"ES": @"Y",
                 @"IT": @"T", @"CA": @"C", @"BE": @"FS", @"CH": @"F", @"NL": @"FS",
                 @"PT": @"PO", @"BR": @"BR", @"MX": @"BE", @"JP": @"J", @"AU": @"X" };
    });
    return map[region ?: @""] ?: @"LL";
}

+ (NSString *)modelNumberForCID:(NSString *)cid region:(NSString *)region {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    IVIdentitySeed(cid, @"mpn", h);
    // Apple retail full-price part numbers look like "M" + 4 chars + region + "/A".
    return [NSString stringWithFormat:@"M%@%@/A", IVCharsFromSeed(h, 4, 3), IVRegionSuffix(region)];
}

@end



