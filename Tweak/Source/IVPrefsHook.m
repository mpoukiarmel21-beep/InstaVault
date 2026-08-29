#import "IVPrefsHook.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <objc/runtime.h>

static NSString *gPrefsContainerPath = nil;

typedef void *(*IVPrefsInitFn)(void *selfObj, SEL _cmd,
                               CFStringRef domain, CFStringRef user, BOOL byHost,
                               CFStringRef containerPath, void *prefs);
static IVPrefsInitFn gOrigPrefsInit = NULL;

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
    if (!container || !container.cid.length) return NO;
    if (gPrefsContainerPath) {
        IVLog(@"PrefsHook: already installed (path=%@)", gPrefsContainerPath);
        return YES;
    }

    Class cls = NSClassFromString(@"CFPrefsPlistSource");
    SEL sel = NSSelectorFromString(@"initWithDomain:user:byHost:containerPath:containingPreferences:");
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) {
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
