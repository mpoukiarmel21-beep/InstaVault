#import "IVLocaleSpoof.h"
#import "IVDiagnostics.h"
#import "vendor/fishhook/fishhook.h"
#import <objc/runtime.h>

#pragma mark - State (held for process lifetime once set)

static NSString *gLocaleIdentifier = nil;                 // "fr_FR" — nil == no locale spoof
static NSString *gTimeZoneName = nil;                     // "Europe/Paris" — nil == real tz
static NSArray<NSString *> *gPreferredLanguages = nil;    // @[@"fr-FR", @"fr"]
static NSLocale *gFixedLocale = nil;                      // captured once, returned by hooks
static NSTimeZone *gFixedTimeZone = nil;                  // captured once, returned by hooks

// UI-language override: the chosen .lproj bundle inside the app + its resolved
// localization name (e.g. "en"). Set once when the container's language actually
// maps to an .lproj Badoo ships. nil == leave the UI language untouched.
static NSBundle *gLprojBundle = nil;
static NSString *gLprojName   = nil;

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

#pragma mark - UI language: NSBundle .lproj override

// A drop-in subclass swapped onto the app's MAIN bundle via object_setClass. Every
// NSLocalizedString / -localizedStringForKey: the app issues then resolves against
// the container's chosen .lproj instead of the phone's system language — this is the
// piece that actually re-renders Badoo's UI in the selected language (the CFPreferences
// / NSLocale seeds alone don't, because UIKit resolves the main bundle's localization
// once, from the system language, before our constructor's other hooks are read).
@interface IVLocalizedBundle : NSBundle
@end
@implementation IVLocalizedBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName {
    NSBundle *b = gLprojBundle;
    if (b) {
        // Sentinel-based miss detection: ask the chosen .lproj with a unique default so
        // we can tell "found in this table" from "absent", and fall back to the app's
        // real resolution for keys that table doesn't carry (never return the key raw).
        static NSString *const kMiss = @"__IV_LPROJ_MISS__";
        NSString *s = [b localizedStringForKey:key value:kMiss table:tableName];
        if (s.length && ![s isEqualToString:kMiss]) return s;
    }
    return [super localizedStringForKey:key value:value table:tableName];
}
- (NSArray<NSString *> *)preferredLocalizations {
    if (gLprojName.length) return @[ gLprojName ];
    return [super preferredLocalizations];
}
- (NSArray<NSString *> *)localizations {
    if (gLprojName.length) return @[ gLprojName ];
    return [super localizations];
}
@end

// Resolve the app-shipped .lproj that best matches the chosen language/region. Tries
// region-qualified ("en-US"), then the bare language ("en"), then the base subtag,
// then a case-insensitive scan of the bundle's own localizations. Sets gLprojBundle
// + returns the matched name, or nil when Badoo ships no such localization.
static NSString *IVResolveLproj(NSString *lang, NSString *region) {
    if (lang.length == 0) return nil;
    NSBundle *main = [NSBundle mainBundle];
    NSMutableArray<NSString *> *cands = [NSMutableArray array];
    if (region.length) [cands addObject:[NSString stringWithFormat:@"%@-%@", lang, region]];
    [cands addObject:lang];
    NSString *base = [[lang componentsSeparatedByString:@"-"] firstObject];
    if (base.length && ![base isEqualToString:lang]) [cands addObject:base];

    for (NSString *c in cands) {
        NSString *path = [main pathForResource:c ofType:@"lproj"];
        if (path) { gLprojBundle = [NSBundle bundleWithPath:path]; return c; }
    }
    for (NSString *loc in main.localizations) {
        for (NSString *c in cands) {
            if ([loc caseInsensitiveCompare:c] == NSOrderedSame) {
                NSString *path = [main pathForResource:loc ofType:@"lproj"];
                if (path) { gLprojBundle = [NSBundle bundleWithPath:path]; return loc; }
            }
        }
    }
    return nil;
}

// Swizzle one NSUserDefaults read (objectForKey:/arrayForKey:/stringForKey:) so a
// container that overrode its language/region answers AppleLanguages / AppleLocale
// with the SPOOFED values — the C-level defaults path many SDKs use to fingerprint
// the device's language list, which the NSLocale swizzles alone don't cover.
static void IVSwizzleUDReader(SEL sel) {
    Method m = class_getInstanceMethod([NSUserDefaults class], sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP repl = imp_implementationWithBlock(^id(id _self, NSString *key) {
        if ([key isKindOfClass:[NSString class]]) {
            if (gPreferredLanguages.count && [key isEqualToString:@"AppleLanguages"]) return gPreferredLanguages;
            if (gLocaleIdentifier.length  && [key isEqualToString:@"AppleLocale"])    return gLocaleIdentifier;
        }
        return ((id (*)(id, SEL, NSString *))orig)(_self, sel, key);
    });
    method_setImplementation(m, repl);
}

#pragma mark - Install

@implementation IVLocaleSpoof

+ (void)installForContainer:(IVContainer *)container {
    if (!container || !container.cid.length) {
        IVLog(@"LocaleSpoof: no active container — no locale spoof");
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

    // 1. Seed AppleLanguages / AppleLocale for C-level defaults readers. Written to the
    //    app's OWN bundle-id domain (NOT kCFPreferencesAnyApplication): IVPrefsHook
    //    redirects the app's non-com.apple domain into the container, so this stays
    //    isolated. Writing the global .GlobalPreferences domain instead could bleed one
    //    container's language into another (or the real account) — a #3 isolation leak.
    //    CFPreferencesCopyAppValue consults the app domain before the global one, so an
    //    app-domain seed is honored while remaining container-scoped.
    CFStringRef appID = (__bridge CFStringRef)([[NSBundle mainBundle] bundleIdentifier] ?: @"com.burbn.instagram");
    if (gPreferredLanguages.count) {
        CFPreferencesSetValue(CFSTR("AppleLanguages"), (__bridge CFArrayRef)gPreferredLanguages,
                              appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    if (gLocaleIdentifier.length) {
        CFPreferencesSetValue(CFSTR("AppleLocale"), (__bridge CFStringRef)gLocaleIdentifier,
                              appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

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

    // 5. UI LANGUAGE — the fix for "Badoo reste en français quand je choisis l'anglais".
    //    Swap the app's main bundle for a subclass that resolves every localized string
    //    against the chosen .lproj. Only when the language actually maps to a shipped
    //    localization (otherwise the UI stays as-is rather than showing raw keys).
    if (lang) {
        NSString *matched = IVResolveLproj(lang, region);
        if (matched && gLprojBundle) {
            gLprojName = [matched copy];
            object_setClass([NSBundle mainBundle], [IVLocalizedBundle class]);
            IVLog(@"LocaleSpoof: UI language bundle -> %@.lproj", matched);
        } else {
            IVErr(@"LocaleSpoof: no shipped .lproj for %@ (region %@) — UI language left as-is",
                  lang, region ?: @"-");
        }
    }

    // 6. NSUserDefaults C-level reads (AppleLanguages / AppleLocale) — the language-list
    //    fingerprint path the NSLocale swizzles don't cover. Also a #3 isolation win: a
    //    container that set no language keeps the real device list, but one that did now
    //    reports ONLY its persona's language, never the phone's.
    IVSwizzleUDReader(@selector(objectForKey:));
    IVSwizzleUDReader(@selector(arrayForKey:));
    IVSwizzleUDReader(@selector(stringForKey:));

    IVLog(@"LocaleSpoof: locale=%@ langs=%@ tz=%@ lproj=%@ rc=%d",
          gLocaleIdentifier, gPreferredLanguages, gTimeZoneName ?: @"real", gLprojName ?: @"none", rc);
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

#pragma mark - Auto-detect (device locale)

// Detect the device's CURRENT system language, mapped onto Badoo's supported list.
// Reads the real preferred languages (not the spoofed ones — this runs before any
// container hooks apply, and must reflect the ACTUAL phone to seed a fresh persona).
// Matching is by base subtag first ("en-GB" → "en"), then by exact tag. Returns nil
// when the phone's language has no supported equivalent.
+ (nullable NSString *)deviceLanguage {
    NSArray<NSString *> *prefs = [NSLocale preferredLanguages];
    if (!prefs.count) return nil;
    NSArray<NSString *> *supported = [self supportedLanguageCodes];
    NSString *primary = prefs.firstObject;
    // Exact match first.
    for (NSString *s in supported) { if ([s caseInsensitiveCompare:primary] == NSOrderedSame) return s; }
    // Base-subtag match: "en-GB" / "en-US" → "en".
    NSString *base = [[primary componentsSeparatedByString:@"-"] firstObject];
    if (base.length) {
        for (NSString *s in supported) { if ([s caseInsensitiveCompare:base] == NSOrderedSame) return s; }
    }
    // Fall back to scanning every preferred language for any supported tag.
    for (NSString *p in prefs) {
        NSString *pb = [[p componentsSeparatedByString:@"-"] firstObject];
        for (NSString *s in supported) {
            if ([s caseInsensitiveCompare:p] == NSOrderedSame || [s caseInsensitiveCompare:pb] == NSOrderedSame) return s;
        }
    }
    return nil;
}

// Detect the device's current country/region from the locale identifier, mapped onto
// the supported region list. nil when unknown.
+ (nullable NSString *)deviceRegion {
    NSLocale *loc = [NSLocale currentLocale];
    NSString *cc = [loc objectForKey:NSLocaleCountryCode];
    if (!cc.length) return nil;
    NSArray<NSString *> *supported = [self supportedRegionCodes];
    for (NSString *s in supported) { if ([s caseInsensitiveCompare:cc] == NSOrderedSame) return s; }
    return nil;
}

@end
