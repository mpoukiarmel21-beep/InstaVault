#import "IVPrefsHook.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <objc/runtime.h>

// The redirected Library/Preferences dir for the active container, held for the
// process lifetime (the swizzled init bridges it to CFStringRef, so it must stay
// alive). nil == hook not installed (default container / install failed).
static NSString *gPrefsContainerPath = nil;

// Original -[CFPrefsPlistSource initWithDomain:user:byHost:containerPath:containingPreferences:].
// Every object here is treated OPAQUELY (void */CFStringRef) so ARC never inserts
// retain/release across the init-family boundary — the classic trap when swizzling
// an -init… under -fobjc-arc. __bridge casts move no ownership.
typedef void *(*IVPrefsInitFn)(void *selfObj, SEL _cmd,
                               CFStringRef domain, CFStringRef user, BOOL byHost,
                               CFStringRef containerPath, void *prefs);
static IVPrefsInitFn gOrigPrefsInit = NULL;

// Replacement init: rewrite the plist PATH of every NON-Apple domain into the
// active container's Library/Preferences (keeping the real appID/domain), so
// NSUserDefaults / CFPreferences for Instagram's own domain read and write inside
// the container instead of the shared process sandbox. com.apple.* domains pass
// through untouched to preserve system behaviour.
//
// AnyUser plists resolve to a system-wide location OUTSIDE the container, so when
// a redirected domain is byUser==AnyUser we also force CurrentUser — otherwise the
// rewritten containerPath would be ignored for that source.
static void *iv_prefsInit(void *selfObj, SEL _cmd,
                          CFStringRef domain, CFStringRef user, BOOL byHost,
                          CFStringRef containerPath, void *prefs) {
    CFStringRef newUser = user;
    CFStringRef newPath = containerPath;

    NSString *domainStr = (__bridge NSString *)domain;
    if (gPrefsContainerPath.length &&
        [domainStr isKindOfClass:[NSString class]] &&
        ![domainStr hasPrefix:@"com.apple."]) {
        newPath = (__bridge CFStringRef)gPrefsContainerPath;
        if (user == NULL || (kCFPreferencesAnyUser && CFEqual(user, kCFPreferencesAnyUser))) {
            newUser = kCFPreferencesCurrentUser;
        }
    }
    return gOrigPrefsInit(selfObj, _cmd, domain, newUser, byHost, newPath, prefs);
}

@implementation IVPrefsHook

+ (BOOL)installForContainer:(IVContainer *)container {
    if (!container || container.isDefault) {
        IVLog(@"PrefsHook: default container — CFPreferences passthrough (no hook)");
        return NO;   // no-op for default; caller never gates on the default path
    }
    if (gPrefsContainerPath) {
        IVLog(@"PrefsHook: already installed (path=%@)", gPrefsContainerPath);
        return YES;
    }

    Class cls = NSClassFromString(@"CFPrefsPlistSource");
    SEL sel = NSSelectorFromString(@"initWithDomain:user:byHost:containerPath:containingPreferences:");
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) {
        // Fail-loud: the private class/selector is gone (OS change). Return NO so
        // Bootstrap reverts the whole isolation to the real sandbox rather than
        // launching with files/keychain isolated but CFPreferences leaking across
        // containers (a cross-container identity leak).
        IVErr(@"PrefsHook: CFPrefsPlistSource init selector ABSENT — cannot isolate CFPreferences");
        return NO;
    }

    NSString *prefsDir = [[IVPaths containerRootForCID:container.cid]
                             stringByAppendingPathComponent:@"Library/Preferences"];
    gPrefsContainerPath = [prefsDir copy];

    gOrigPrefsInit = (IVPrefsInitFn)method_setImplementation(m, (IMP)iv_prefsInit);
    if (!gOrigPrefsInit) {
        IVErr(@"PrefsHook: method_setImplementation returned NULL original — aborting");
        gPrefsContainerPath = nil;
        return NO;
    }
    IVLog(@"PrefsHook: CFPreferences redirected -> %@", gPrefsContainerPath);
    return YES;
}

@end
