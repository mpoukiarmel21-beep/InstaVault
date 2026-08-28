#import "IVLocaleSpoof.h"
#import "../Util/IVDiagnostics.h"
#import "../vendor/fishhook/fishhook.h"
#import <objc/runtime.h>

#pragma mark - State (held for process lifetime once set)

static NSString *gLocaleIdentifier = nil;                 // "fr_FR" — nil == no locale spoof
static NSString *gTimeZoneName = nil;                     // "Europe/Paris" — nil == real tz
static NSArray<NSString *> *gPreferredLanguages = nil;    // @[@"fr-FR", @"fr"]
static NSLocale *gFixedLocale = nil;                      // captured once, returned by hooks
static NSTimeZone *gFixedTimeZone = nil;                  // captured once, returned by hooks

// Saved CF originals (fishhook, app-binary imports only).
static CFLocaleRef   (*orig_CFLocaleCopyCurrent)(void)   = NULL;
static CFTimeZoneRef (*orig_CFTimeZoneCopySystem)(void)  = NULL;
static CFTimeZoneRef (*orig_CFTimeZoneCopyDefault)(void) = NULL;

#pragma mark - Region -> timezone

// A representative IANA timezone per region. Unknown region -> nil (real tz kept).
static NSString *IVTimeZoneForRegion(NSString *region) {
    static NSDictionary<NSString *, NSString *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"US": @"America/New_York", @"FR": @"Europe/Paris",   @"GB": @"Europe/London",
            @"DE": @"Europe/Berlin",    @"ES": @"Europe/Madrid",  @"IT": @"Europe/Rome",
            @"CA": @"America/Toronto",  @"BE": @"Europe/Brussels", @"CH": @"Europe/Zurich",
            @"NL": @"Europe/Amsterdam", @"PT": @"Europe/Lisbon",  @"BR": @"America/Sao_Paulo",
            @"MX": @"America/Mexico_City", @"JP": @"Asia/Tokyo",  @"AU": @"Australia/Sydney",
            @"IN": @"Asia/Kolkata",     @"RU": @"Europe/Moscow",  @"KR": @"Asia/Seoul",
            @"CN": @"Asia/Shanghai",    @"TR": @"Europe/Istanbul", @"ID": @"Asia/Jakarta",
            @"TH": @"Asia/Bangkok",     @"VN": @"Asia/Ho_Chi_Minh", @"PL": @"Europe/Warsaw",
            @"SE": @"Europe/Stockholm", @"AE": @"Asia/Dubai",     @"EG": @"Africa/Cairo",
            @"MA": @"Africa/Casablanca", @"SN": @"Africa/Dakar",  @"CI": @"Africa/Abidjan",
            @"NG": @"Africa/Lagos",     @"ZA": @"Africa/Johannesburg",
        };
    });
    return map[region ?: @""];
}

#pragma mark - Swizzle helper (class methods)

static void IVSwizzleClassMethod(Class cls, SEL sel, id block) {
    if (!cls) return;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return;
    method_setImplementation(m, imp_implementationWithBlock(block));
}

#pragma mark - CF-level hooks

static CFLocaleRef iv_CFLocaleCopyCurrent(void) {
    if (gLocaleIdentifier.length) {
        CFLocaleRef l = CFLocaleCreate(kCFAllocatorDefault, (__bridge CFStringRef)gLocaleIdentifier);
        if (l) return l;   // +1, as the real CFLocaleCopyCurrent contract requires
    }
    return orig_CFLocaleCopyCurrent();
}

static CFTimeZoneRef iv_CFTimeZoneCopySystem(void) {
    if (gTimeZoneName.length) {
        CFTimeZoneRef tz = CFTimeZoneCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)gTimeZoneName, true);
        if (tz) return tz;
    }
    return orig_CFTimeZoneCopySystem();
}

static CFTimeZoneRef iv_CFTimeZoneCopyDefault(void) {
    if (gTimeZoneName.length) {
        CFTimeZoneRef tz = CFTimeZoneCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)gTimeZoneName, true);
        if (tz) return tz;
    }
    return orig_CFTimeZoneCopyDefault();
}

#pragma mark - Install

@implementation IVLocaleSpoof

+ (void)installForContainer:(IVContainer *)container {
    if (!container || container.isDefault) {
        IVLog(@"LocaleSpoof: default container — no locale spoof");
        return;
    }
    NSString *lang   = container.appLanguage.length   ? container.appLanguage   : nil;
    NSString *region = container.regionCountry.length ? container.regionCountry : nil;
    if (!lang && !region) {
        IVLog(@"LocaleSpoof: container sets no language/region — no-op");
        return;
    }

    // Canonical locale identifier from the chosen components (e.g. "fr_FR").
    NSMutableDictionary *comp = [NSMutableDictionary dictionary];
    if (lang)   comp[NSLocaleLanguageCode] = lang;
    if (region) comp[NSLocaleCountryCode]  = region;
    gLocaleIdentifier = [[NSLocale localeIdentifierFromComponents:comp] copy];
    gFixedLocale = [NSLocale localeWithLocaleIdentifier:gLocaleIdentifier];

    // Preferred-languages list drives NSBundle localization: region-qualified tag
    // first (e.g. "fr-FR"), then the bare language as a fallback.
    if (lang) {
        NSString *tag = region ? [NSString stringWithFormat:@"%@-%@", lang, region] : lang;
        gPreferredLanguages = [tag isEqualToString:lang] ? @[ lang ] : @[ tag, lang ];
    }
    if (region) {
        NSString *tzName = IVTimeZoneForRegion(region);
        gFixedTimeZone = tzName ? [NSTimeZone timeZoneWithName:tzName] : nil;
        gTimeZoneName = gFixedTimeZone ? [tzName copy] : nil;   // only spoof tz if resolvable
    }

    // 1. Seed AppleLanguages / AppleLocale into the container's (already-redirected
    //    by IVPrefsHook) preferences, so NSBundle loads the matching .lproj. This
    //    runs in the launch constructor, before UIKit reads localization.
    if (gPreferredLanguages.count) {
        CFPreferencesSetValue(CFSTR("AppleLanguages"), (__bridge CFArrayRef)gPreferredLanguages,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    if (gLocaleIdentifier.length) {
        CFPreferencesSetValue(CFSTR("AppleLocale"), (__bridge CFStringRef)gLocaleIdentifier,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    // 2. NSLocale ObjC surfaces — return the fixed locale (captured once to avoid
    //    rebuilding, and to keep the closure independent of the swizzled methods).
    if (gFixedLocale) {
        NSLocale *(^loc)(id) = ^NSLocale *(id _self) { return gFixedLocale; };
        IVSwizzleClassMethod([NSLocale class], @selector(currentLocale), loc);
        IVSwizzleClassMethod([NSLocale class], @selector(autoupdatingCurrentLocale), loc);
    }
    if (gPreferredLanguages.count) {
        IVSwizzleClassMethod([NSLocale class], @selector(preferredLanguages),
                             ^NSArray<NSString *> *(id _self) { return gPreferredLanguages; });
    }

    // 3. NSTimeZone ObjC surfaces — only when the region resolved to a real tz, so
    //    the fixed value can never be nil (which would break date math).
    if (gFixedTimeZone) {
        NSTimeZone *(^tz)(id) = ^NSTimeZone *(id _self) { return gFixedTimeZone; };
        IVSwizzleClassMethod([NSTimeZone class], @selector(systemTimeZone),  tz);
        IVSwizzleClassMethod([NSTimeZone class], @selector(localTimeZone),   tz);
        IVSwizzleClassMethod([NSTimeZone class], @selector(defaultTimeZone), tz);
    }

    // 4. CF-level fishhook for C callers in the app binary.
    struct rebinding r[3];
    int n = 0;
    if (gLocaleIdentifier.length) {
        r[n++] = (struct rebinding){"CFLocaleCopyCurrent", (void *)iv_CFLocaleCopyCurrent, (void **)&orig_CFLocaleCopyCurrent};
    }
    if (gTimeZoneName.length) {
        r[n++] = (struct rebinding){"CFTimeZoneCopySystem",  (void *)iv_CFTimeZoneCopySystem,  (void **)&orig_CFTimeZoneCopySystem};
        r[n++] = (struct rebinding){"CFTimeZoneCopyDefault", (void *)iv_CFTimeZoneCopyDefault, (void **)&orig_CFTimeZoneCopyDefault};
    }
    int rc = (n > 0) ? rebind_symbols(r, n) : 0;

    IVLog(@"LocaleSpoof: locale=%@ langs=%@ tz=%@ rc=%d",
          gLocaleIdentifier, gPreferredLanguages, gTimeZoneName ?: @"real", rc);
}

#pragma mark - Option sources

+ (NSLocale *)frLocale {
    static NSLocale *fr = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fr = [NSLocale localeWithLocaleIdentifier:@"fr_FR"]; });
    return fr;
}

+ (NSArray<NSString *> *)supportedLanguageCodes {
    return @[ @"en", @"fr", @"es", @"pt", @"de", @"it", @"nl", @"ar", @"ru", @"tr",
              @"hi", @"id", @"th", @"vi", @"pl", @"sv", @"ja", @"ko", @"zh-Hans", @"zh-Hant" ];
}

+ (NSString *)displayNameForLanguage:(NSString *)code {
    if (code.length == 0) return @"";
    NSString *name = [[self frLocale] localizedStringForLocaleIdentifier:code];
    if (name.length == 0) name = [[self frLocale] localizedStringForLanguageCode:code];
    return name.length ? [name capitalizedStringWithLocale:[self frLocale]] : code;
}

+ (NSArray<NSString *> *)supportedRegionCodes {
    return @[ @"US", @"FR", @"GB", @"DE", @"ES", @"IT", @"CA", @"BE", @"CH", @"NL",
              @"PT", @"BR", @"MX", @"JP", @"AU", @"IN", @"RU", @"KR", @"CN", @"TR",
              @"ID", @"TH", @"VN", @"PL", @"SE", @"AE", @"EG", @"MA", @"SN", @"CI",
              @"NG", @"ZA" ];
}

+ (NSString *)displayNameForRegion:(NSString *)code {
    if (code.length == 0) return @"";
    NSString *name = [[self frLocale] localizedStringForCountryCode:code];
    return name.length ? name : code;
}

@end
