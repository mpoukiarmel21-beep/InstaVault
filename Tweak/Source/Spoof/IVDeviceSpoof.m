#import "IVDeviceSpoof.h"
#import "../Core/IVContainerStore.h"
#import "../Util/IVDiagnostics.h"
#import "../vendor/fishhook/fishhook.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <errno.h>
#import <string.h>

#pragma mark - Deterministic seed

// 32-byte SHA256(cid). Stable across launches, unique per container.
static void IVSeedBytes(NSString *cid, unsigned char out[CC_SHA256_DIGEST_LENGTH]) {
    NSData *d = [(cid ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(d.bytes, (CC_LONG)d.length, out);
}

// A stable NSUUID derived from SHA256(cid + tag) — first 16 bytes as the UUID.
static NSUUID *IVSeededUUID(NSString *cid, NSString *tag) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    IVSeedBytes([NSString stringWithFormat:@"%@|%@", cid, tag], h);
    return [[NSUUID alloc] initWithUUIDBytes:h];
}

#pragma mark - State

static NSString *gSpoofedModel = nil;   // e.g. @"iPhone14,2"
static char *gSpoofedModelC = NULL;     // strdup for C-level hooks
static NSString *gVendorUUID = nil;     // IDFV string
static NSString *gAdvUUID = nil;        // IDFA string

// Saved originals.
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;
static int (*orig_uname)(struct utsname *) = NULL;

@implementation IVDeviceSpoof

+ (NSArray<NSString *> *)availableModels {
    // iOS 26–capable models (A13 Bionic and newer): iPhone 11 → iPhone 16 line.
    // (iPhone XS/XR = A12 = iPhone11,x are dropped by iOS 26, so they are absent.)
    return @[ @"iPhone12,1", @"iPhone12,3", @"iPhone12,5", @"iPhone12,8",   // 11 / 11 Pro / Max / SE2
              @"iPhone13,1", @"iPhone13,2", @"iPhone13,3", @"iPhone13,4",   // 12 mini/12/Pro/Max
              @"iPhone14,4", @"iPhone14,5", @"iPhone14,2", @"iPhone14,3",   // 13 mini/13/Pro/Max
              @"iPhone14,6", @"iPhone14,7", @"iPhone14,8",                   // SE3 / 14 / 14 Plus
              @"iPhone15,2", @"iPhone15,3", @"iPhone15,4", @"iPhone15,5",   // 14 Pro/Max / 15 / 15 Plus
              @"iPhone16,1", @"iPhone16,2",                                  // 15 Pro / 15 Pro Max
              @"iPhone17,3", @"iPhone17,4", @"iPhone17,1", @"iPhone17,2" ]; // 16 / 16 Plus / 16 Pro / Max
}

+ (NSString *)effectiveModelForContainer:(IVContainer *)container {
    if (container.deviceModel.length) return container.deviceModel;   // explicit override
    NSArray<NSString *> *models = [self availableModels];
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    IVSeedBytes(container.cid, h);
    NSUInteger idx = ((NSUInteger)h[0] << 8 | h[1]) % models.count;    // stable pick
    return models[idx];
}

#pragma mark - C-level hooks

static int iv_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (gSpoofedModelC && name && strcmp(name, "hw.machine") == 0) {
        size_t need = strlen(gSpoofedModelC) + 1;
        if (!oldp) { if (oldlenp) *oldlenp = need; return 0; }        // size query
        if (!oldlenp) { errno = EINVAL; return -1; }                 // buffer with no length — copying would overflow
        if (*oldlenp < need) { errno = ENOMEM; return -1; }          // caller's buffer too small
        memcpy(oldp, gSpoofedModelC, need);
        *oldlenp = need;
        return 0;
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static int iv_uname(struct utsname *u) {
    int r = orig_uname(u);
    if (r == 0 && gSpoofedModelC && u) {
        strlcpy(u->machine, gSpoofedModelC, sizeof(u->machine));
    }
    return r;
}

#pragma mark - Install

static void IVSwizzleReturningUUID(Class cls, SEL sel, NSString *(^uuidStr)(void)) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^NSUUID *(id _self) {
        return [[NSUUID alloc] initWithUUIDString:uuidStr()];
    });
    method_setImplementation(m, imp);
}

+ (void)installForContainer:(IVContainer *)container {
    if (!container || container.isDefault) {
        IVLog(@"DeviceSpoof: default container — no spoofing");
        return;
    }

    gSpoofedModel = [self effectiveModelForContainer:container];
    if (gSpoofedModelC) { free(gSpoofedModelC); gSpoofedModelC = NULL; }
    gSpoofedModelC = strdup(gSpoofedModel.UTF8String);
    gVendorUUID = [IVSeededUUID(container.cid, @"idfv").UUIDString copy];
    gAdvUUID = [IVSeededUUID(container.cid, @"idfa").UUIDString copy];

    // IDFV — every app on a device shares one, so per-container is plausible.
    IVSwizzleReturningUUID([UIDevice class], @selector(identifierForVendor), ^NSString *{ return gVendorUUID; });

    // IDFA — ASIdentifierManager may be absent; look it up dynamically.
    // NB: `asm` is a reserved keyword in clang's GNU dialect (inline assembly),
    // so the class variable MUST NOT be named `asm` — it fails to compile.
    Class asmCls = NSClassFromString(@"ASIdentifierManager");
    IVSwizzleReturningUUID(asmCls, NSSelectorFromString(@"advertisingIdentifier"), ^NSString *{ return gAdvUUID; });

    // hw.machine via sysctlbyname + uname.
    struct rebinding r[] = {
        {"sysctlbyname", (void *)iv_sysctlbyname, (void **)&orig_sysctlbyname},
        {"uname",        (void *)iv_uname,        (void **)&orig_uname},
    };
    int rc = rebind_symbols(r, sizeof(r) / sizeof(r[0]));
    IVLog(@"DeviceSpoof: model=%@ idfv=%@ rc=%d", gSpoofedModel, gVendorUUID, rc);
}

@end

