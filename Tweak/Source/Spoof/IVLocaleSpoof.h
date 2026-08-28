#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Per-container app language + region/country spoofing (plan-directeur §7, gear
/// affordance). When a container pins an app language and/or a region, this makes
/// the process answer that identity on every locale surface Instagram reads:
///
///   • App UI language — seeds AppleLanguages / AppleLocale into the container's
///     (already-redirected) preferences so NSBundle loads the matching .lproj.
///   • NSLocale.currentLocale / autoupdatingCurrentLocale / preferredLanguages.
///   • NSTimeZone.systemTimeZone / localTimeZone / defaultTimeZone (region → tz).
///   • CFLocaleCopyCurrent / CFTimeZoneCopySystem (fishhook, for C-level callers
///     in the app binary).
///
/// Gated on ACTIVE isolation: never touches locale state on the real (default)
/// account, and is a no-op when the container sets neither language nor region.
///
/// Deliberately NOT spoofed: carrier / CoreTelephony (MCC/MNC). A fabricated
/// carrier that disagrees with the real IP geolocation is a fingerprint tell, and
/// a sandboxed app cannot verify the real one — so carrier is left untouched.
@interface IVLocaleSpoof : NSObject

/// Install the locale/timezone hooks + seed the redirected preferences for the
/// given container. No-op for the default container or when it sets no
/// language/region. Run once at launch, AFTER isolation is confirmed active.
+ (void)installForContainer:(IVContainer *)container;

#pragma mark - Option sources (for the settings picker)

/// Selectable app-language ISO codes (e.g. "fr", "en", "zh-Hans"), Instagram's
/// commonly-supported set.
+ (NSArray<NSString *> *)supportedLanguageCodes;

/// French display name for a language code (UI language is French).
+ (NSString *)displayNameForLanguage:(NSString *)code;

/// Selectable region/country ISO codes (e.g. "FR", "US").
+ (NSArray<NSString *> *)supportedRegionCodes;

/// French display name for a region code.
+ (NSString *)displayNameForRegion:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
