#import <Foundation/Foundation.h>
#import "IVContainerManager.h"

// Per-container NSHTTPCookieStorage isolation via ObjC swizzling

static IMP orig_sharedHTTPCookieStorage;
static id hooked_sharedHTTPCookieStorage(id self, SEL _cmd) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *path = active.cookiePath;
        NSHTTPCookieStorage *store = [[NSHTTPCookieStorage alloc] initWithStorageLocation:[NSURL fileURLWithPath:path]];
        return store;
    }
    return ((id(*)(id, SEL))orig_sharedHTTPCookieStorage)(self, _cmd);
}

static IMP orig_cookies;
static NSArray *hooked_cookies(id self, SEL _cmd) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *path = active.cookiePath;
        NSHTTPCookieStorage *store = [[NSHTTPCookieStorage alloc] initWithStorageLocation:[NSURL fileURLWithPath:path]];
        return [store cookies];
    }
    return ((NSArray *(*)(id, SEL))orig_cookies)(self, _cmd);
}

static IMP orig_setCookie;
static void hooked_setCookie(id self, SEL _cmd, id cookie) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *path = active.cookiePath;
        NSHTTPCookieStorage *store = [[NSHTTPCookieStorage alloc] initWithStorageLocation:[NSURL fileURLWithPath:path]];
        [store setCookie:cookie];
        return;
    }
    ((void(*)(id, SEL, id))orig_setCookie)(self, _cmd, cookie);
}

static IMP orig_deleteCookie;
static void hooked_deleteCookie(id self, SEL _cmd, id cookie) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *path = active.cookiePath;
        NSHTTPCookieStorage *store = [[NSHTTPCookieStorage alloc] initWithStorageLocation:[NSURL fileURLWithPath:path]];
        [store deleteCookie:cookie];
        return;
    }
    ((void(*)(id, SEL, id))orig_deleteCookie)(self, _cmd, cookie);
}

__attribute__((constructor))
static void IVInstallCookieHook(void) {
    Class storage = objc_getClass("NSHTTPCookieStorage");
    if (!storage) return;

    Method m_shared = class_getClassMethod(storage, @selector(sharedHTTPCookieStorage));
    if (m_shared) {
        orig_sharedHTTPCookieStorage = method_getImplementation(m_shared);
        method_setImplementation(m_shared, (IMP)hooked_sharedHTTPCookieStorage);
    }

    Method m_cookies = class_getInstanceMethod(storage, @selector(cookies));
    if (m_cookies) {
        orig_cookies = method_getImplementation(m_cookies);
        method_setImplementation(m_cookies, (IMP)hooked_cookies);
    }

    Method m_set = class_getInstanceMethod(storage, @selector(setCookie:));
    if (m_set) {
        orig_setCookie = method_getImplementation(m_set);
        method_setImplementation(m_set, (IMP)hooked_setCookie);
    }

    Method m_del = class_getInstanceMethod(storage, @selector(deleteCookie:));
    if (m_del) {
        orig_deleteCookie = method_getImplementation(m_del);
        method_setImplementation(m_del, (IMP)hooked_deleteCookie);
    }

    NSLog(@"[InstaVault] NSHTTPCookieStorage hooks installed");
}