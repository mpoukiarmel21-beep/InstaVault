#import "IVDeviceSpoof.h"
#import "IVDeviceIdentity.h"
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

// iOS-version spoof (nil / NULL == report the real OS version untouched).
static NSString *gSpoofedIOSVersion = nil;   // marketing, e.g. @"26.6.1"
static NSString *gSpoofedBuild = nil;        // build,     e.g. @"23G83"
static char *gSpoofedProductVersionC = NULL; // kern.osproductversion
static char *gSpoofedBuildC = NULL;          // kern.osversion

// Saved originals.
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;
static int (*orig_uname)(struct utsname *) = NULL;

@implementation IVDeviceSpoof

+ (NSString *)effectiveModelForContainer:(IVContainer *)container {
    if (container.deviceModel.length) return container.deviceModel;   // explicit override
    // No explicit model: default to the newest model on the REAL chip family, so
    // display + spoof stay consistent with the anti-fingerprint constraint.
    return [IVDeviceIdentity defaultModel].identifier;
}

#pragma mark - Version parsing

static NSOperatingSystemVersion IVParseOSVersion(NSString *v) {
    NSOperatingSystemVersion o = {0, 0, 0};
    NSArray<NSString *> *p = [(v ?: @"") componentsSeparatedByString:@"."];
    if (p.count > 0) o.majorVersion = [p[0] integerValue];
    if (p.count > 1) o.minorVersion = [p[1] integerValue];
    if (p.count > 2) o.patchVersion = [p[2] integerValue];
    return o;
}

#pragma mark - C-level hooks

static int iv_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    // Resolve the spoofed C string for the requested key (NULL == not spoofed).
    const char *spoof = NULL;
    if (name) {
        if (gSpoofedModelC && strcmp(name, "hw.machine") == 0) {
            spoof = gSpoofedModelC;
        } else if (gSpoofedProductVersionC && strcmp(name, "kern.osproductversion") == 0) {
            spoof = gSpoofedProductVersionC;
        } else if (gSpoofedBuildC && strcmp(name, "kern.osversion") == 0) {
            spoof = gSpoofedBuildC;
        }
    }
    if (spoof) {
        size_t need = strlen(spoof) + 1;
        if (!oldp) { if (oldlenp) *oldlenp = need; return 0; }        // size query
        if (!oldlenp) { errno = EINVAL; return -1; }                 // buffer with no length — copying would overflow
        if (*oldlenp < need) { errno = ENOMEM; return -1; }          // caller's buffer too small
        memcpy(oldp, spoof, need);
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

// Raw MIB path: sysctl({CTL_HW, HW_MACHINE}) — some fingerprint libraries read
// the model this way instead of the string API. Mirror the hw.machine spoof with
// the same size-query / ENOMEM contract. Only HW_MACHINE is touched: HW_MODEL
// returns the board id (e.g. "D79AP"), a different value we must NOT rewrite to
// the marketing identifier or it would be internally inconsistent.
static int iv_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (gSpoofedModelC && name && namelen >= 2 && name[0] == CTL_HW && name[1] == HW_MACHINE) {
        const char *spoof = gSpoofedModelC;
        size_t need = strlen(spoof) + 1;
        if (!oldp) { if (oldlenp) *oldlenp = need; return 0; }        // size query
        if (!oldlenp) { errno = EINVAL; return -1; }                 // buffer with no length
        if (*oldlenp < need) { errno = ENOMEM; return -1; }          // caller's buffer too small
        memcpy(oldp, spoof, need);
        *oldlenp = need;
        return 0;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

#pragma mark - ObjC swizzle helpers

static void IVSwizzleReturningUUID(Class cls, SEL sel, NSString *(^uuidStr)(void)) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^NSUUID *(id _self) {
        return [[NSUUID alloc] initWithUUIDString:uuidStr()];
    });
    method_setImplementation(m, imp);
}

static void IVSwizzleReturningString(Class cls, SEL sel, NSString *(^str)(void)) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^NSString *(id _self) { return str(); });
    method_setImplementation(m, imp);
}

// Install the coordinated iOS-version surfaces. Only called when the container
// pins a version AND we can resolve its real build number — so the three OS-level
// answers (marketing version, struct, build) always agree.
static void IVInstallIOSVersionSpoof(void) {
    if (gSpoofedIOSVersion.length == 0) return;

    // UIDevice.systemVersion -> marketing string.
    IVSwizzleReturningString([UIDevice class], @selector(systemVersion),
                             ^NSString *{ return gSpoofedIOSVersion; });

    // NSProcessInfo.operatingSystemVersionString -> Apple's "Version X (Build Y)".
    IVSwizzleReturningString([NSProcessInfo class], @selector(operatingSystemVersionString),
                             ^NSString *{
        return [NSString stringWithFormat:@"Version %@ (Build %@)",
                gSpoofedIOSVersion, gSpoofedBuild ?: @""];
    });

    // NSProcessInfo.operatingSystemVersion -> struct parsed from the marketing string.
    Method mv = class_getInstanceMethod([NSProcessInfo class], @selector(operatingSystemVersion));
    if (mv) {
        IMP imp = imp_implementationWithBlock(^NSOperatingSystemVersion(id _self) {
            return IVParseOSVersion(gSpoofedIOSVersion);
        });
        method_setImplementation(mv, imp);
    }
}

#pragma mark - Install

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

    // iOS version — only when the container pins one AND its build resolves, so
    // kern.osproductversion / kern.osversion / UIDevice / NSProcessInfo agree.
    if (container.iosVersion.length) {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:container.iosVersion];
        if (build.length) {
            gSpoofedIOSVersion = [container.iosVersion copy];
            gSpoofedBuild = [build copy];
            if (gSpoofedProductVersionC) { free(gSpoofedProductVersionC); gSpoofedProductVersionC = NULL; }
            if (gSpoofedBuildC) { free(gSpoofedBuildC); gSpoofedBuildC = NULL; }
            gSpoofedProductVersionC = strdup(gSpoofedIOSVersion.UTF8String);
            gSpoofedBuildC = strdup(gSpoofedBuild.UTF8String);
        } else {
            IVErr(@"DeviceSpoof: no build number for iOS %@ — leaving OS version real", container.iosVersion);
        }
    }

    // IDFV — every app on a device shares one, so per-container is plausible.
    IVSwizzleReturningUUID([UIDevice class], @selector(identifierForVendor), ^NSString *{ return gVendorUUID; });

    // IDFA — ASIdentifierManager may be absent; look it up dynamically.
    // NB: `asm` is a reserved keyword in clang's GNU dialect (inline assembly),
    // so the class variable MUST NOT be named `asm` — it fails to compile.
    Class asmCls = NSClassFromString(@"ASIdentifierManager");
    IVSwizzleReturningUUID(asmCls, NSSelectorFromString(@"advertisingIdentifier"), ^NSString *{ return gAdvUUID; });

    // iOS-version ObjC surfaces (no-op when unset above).
    IVInstallIOSVersionSpoof();

    // hw.machine (+ kern.os* when set) via sysctlbyname + sysctl (raw MIB) + uname.
    struct rebinding r[] = {
        {"sysctlbyname", (void *)iv_sysctlbyname, (void **)&orig_sysctlbyname},
        {"sysctl",       (void *)iv_sysctl,       (void **)&orig_sysctl},
        {"uname",        (void *)iv_uname,        (void **)&orig_uname},
    };
    int rc = rebind_symbols(r, sizeof(r) / sizeof(r[0]));
    IVLog(@"DeviceSpoof: model=%@ ios=%@ (build %@) idfv=%@ rc=%d",
          gSpoofedModel, gSpoofedIOSVersion ?: @"real", gSpoofedBuild ?: @"-", gVendorUUID, rc);
}

@end
