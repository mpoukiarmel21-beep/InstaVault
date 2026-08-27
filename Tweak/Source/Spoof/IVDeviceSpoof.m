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
#import <dlfcn.h>
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

// `nchars` uppercase hex characters from SHA256(cid + tag). Deterministic.
static NSString *IVSeededHex(NSString *cid, NSString *tag, NSUInteger nchars) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    IVSeedBytes([NSString stringWithFormat:@"%@|%@", cid, tag], h);
    NSMutableString *s = [NSMutableString stringWithCapacity:nchars];
    for (NSUInteger i = 0; i < nchars; i++) {
        [s appendFormat:@"%1X", h[i % CC_SHA256_DIGEST_LENGTH] >> ((i & 1) ? 0 : 4) & 0xF];
    }
    return s;
}

// A plausible modern-iPhone UDID: 8 hex + '-' + 16 hex (25 chars), e.g.
// "00008120-0011223344556677". Deterministic per cid.
static NSString *IVSeededUDID(NSString *cid) {
    return [NSString stringWithFormat:@"%@-%@",
            IVSeededHex(cid, @"udid-hi", 8), IVSeededHex(cid, @"udid-lo", 16)];
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

// MobileGestalt spoof (P3) — per-container device identity as libMobileGestalt
// reports it. Populated only for non-default containers, keyed by the exact
// property string Instagram's anti-fraud code queries. Everything not in this
// dictionary passes straight through to the real MGCopyAnswer. ProductType is
// pinned to the SAME model string as hw.machine so the two never disagree (an
// unspoofed ProductType alongside a spoofed hw.machine is itself a tamper tell).
static NSDictionary<NSString *, NSString *> *gGestaltSpoof = nil;

// Saved originals.
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;
static int (*orig_uname)(struct utsname *) = NULL;
static CFPropertyListRef (*orig_MGCopyAnswer)(CFStringRef) = NULL;
static void *(*orig_dlsym)(void *, const char *) = NULL;

@implementation IVDeviceSpoof

+ (NSString *)effectiveModelForContainer:(IVContainer *)container {
    if (container.deviceModel.length) return container.deviceModel;   // explicit override
    // No explicit model: a UNIQUE per-cid model on the REAL chip family, so two
    // no-model containers (e.g. legacy ones created before per-container seeding)
    // never collide on the same identifier. Stays within the anti-fingerprint
    // constraint (never leaves the real chip family).
    return [IVDeviceIdentity seededModelForCID:container.cid].identifier;
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

#pragma mark - MobileGestalt hook (P3)

// libMobileGestalt's MGCopyAnswer is THE canonical device-identity oracle: it
// answers UniqueDeviceID, SerialNumber, ProductType, etc. Instagram's anti-fraud
// layer reads it to fingerprint the handset, so two containers that both report
// the real values look like one device with many accounts (the captcha trigger).
// We return per-container deterministic answers for a tight identity whitelist and
// pass everything else through untouched. Returned values are +1 retained
// (CFBridgingRetain), honoring the "Copy" ownership contract the caller expects.
static CFPropertyListRef iv_MGCopyAnswer(CFStringRef property) {
    if (property && gGestaltSpoof) {
        NSString *key = (__bridge NSString *)property;
        NSString *val = gGestaltSpoof[key];
        if (val) return (CFPropertyListRef)CFBridgingRetain(val);
    }
    if (orig_MGCopyAnswer) return orig_MGCopyAnswer(property);
    return NULL;
}

// Many apps resolve MGCopyAnswer at runtime via dlsym (the symbol is private, so
// it is rarely bound statically). fishhook can only rebind statically-bound
// imports, so we ALSO intercept dlsym and hand back our replacement whenever the
// exact "MGCopyAnswer" symbol is requested. Every other lookup — including the
// multi-argument "MGCopyAnswerWithError" (a different ABI we must never alias to
// our 1-arg function) — passes straight through to the real dlsym.
static void *iv_dlsym(void *handle, const char *symbol) {
    if (symbol && strcmp(symbol, "MGCopyAnswer") == 0 && orig_MGCopyAnswer) {
        return (void *)iv_MGCopyAnswer;
    }
    return orig_dlsym ? orig_dlsym(handle, symbol) : NULL;
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

    // MobileGestalt identity whitelist (P3). ProductType MUST equal the spoofed
    // hw.machine model, or the two disagree and betray the spoof. SerialNumber is
    // sourced from IVDeviceIdentity — the SAME value the device-info sheet shows
    // the user — so a container's serial is identical wherever it surfaces (one
    // container == one phone). ProductVersion/BuildVersion are added below only
    // when the OS version is actually spoofed, keeping MobileGestalt consistent
    // with the kern.os* sysctl answers.
    NSMutableDictionary<NSString *, NSString *> *gestalt = [NSMutableDictionary dictionaryWithDictionary:@{
        @"UniqueDeviceID": IVSeededUDID(container.cid),
        @"SerialNumber":   [IVDeviceIdentity serialForCID:container.cid],
        @"ProductType":    gSpoofedModel ?: @"",
    }];

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

    // Mirror the resolved OS version into MobileGestalt so ProductVersion/
    // BuildVersion never contradict the sysctl kern.os* spoof. Left untouched
    // (real passthrough) when the container pins no version.
    if (gSpoofedIOSVersion.length) {
        gestalt[@"ProductVersion"] = gSpoofedIOSVersion;
        if (gSpoofedBuild.length) gestalt[@"BuildVersion"] = gSpoofedBuild;
    }
    gGestaltSpoof = [gestalt copy];

    // IDFV — every app on a device shares one, so per-container is plausible.
    IVSwizzleReturningUUID([UIDevice class], @selector(identifierForVendor), ^NSString *{ return gVendorUUID; });

    // IDFA — ASIdentifierManager may be absent; look it up dynamically.
    // NB: `asm` is a reserved keyword in clang's GNU dialect (inline assembly),
    // so the class variable MUST NOT be named `asm` — it fails to compile.
    Class asmCls = NSClassFromString(@"ASIdentifierManager");
    IVSwizzleReturningUUID(asmCls, NSSelectorFromString(@"advertisingIdentifier"), ^NSString *{ return gAdvUUID; });

    // iOS-version ObjC surfaces (no-op when unset above).
    IVInstallIOSVersionSpoof();

    // Resolve the REAL MGCopyAnswer BEFORE rebinding dlsym (so this lookup uses
    // the genuine dlsym, not our interceptor). libMobileGestalt is loaded by
    // UIKit in every UI process, so RTLD_DEFAULT finds it; fall back to an
    // explicit dlopen if the shared-cache search misses.
    orig_MGCopyAnswer = (CFPropertyListRef (*)(CFStringRef))dlsym(RTLD_DEFAULT, "MGCopyAnswer");
    if (!orig_MGCopyAnswer) {
        void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (mg) orig_MGCopyAnswer = (CFPropertyListRef (*)(CFStringRef))dlsym(mg, "MGCopyAnswer");
    }

    // hw.machine (+ kern.os* when set) via sysctlbyname + sysctl (raw MIB) + uname,
    // plus MobileGestalt: rebind the bound MGCopyAnswer import AND intercept dlsym
    // to cover the (common) runtime-resolved path. Only wired when the real
    // MGCopyAnswer resolved, so a miss degrades to no MobileGestalt spoof rather
    // than a NULL-forward crash.
    struct rebinding r[] = {
        {"sysctlbyname", (void *)iv_sysctlbyname, (void **)&orig_sysctlbyname},
        {"sysctl",       (void *)iv_sysctl,       (void **)&orig_sysctl},
        {"uname",        (void *)iv_uname,        (void **)&orig_uname},
        {"MGCopyAnswer", (void *)iv_MGCopyAnswer, (void **)&orig_MGCopyAnswer},
        {"dlsym",        (void *)iv_dlsym,        (void **)&orig_dlsym},
    };
    // Drop the MobileGestalt pair if we could not resolve the original.
    unsigned count = orig_MGCopyAnswer ? (sizeof(r) / sizeof(r[0])) : 3;
    int rc = rebind_symbols(r, count);
    IVLog(@"DeviceSpoof: model=%@ ios=%@ (build %@) idfv=%@ udid=%@ mg=%d rc=%d",
          gSpoofedModel, gSpoofedIOSVersion ?: @"real", gSpoofedBuild ?: @"-",
          gVendorUUID, gGestaltSpoof[@"UniqueDeviceID"], (orig_MGCopyAnswer != NULL), rc);
}

@end
