#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "IVContainerManager.h"
#import "IVContainer.h"

@interface NSHTTPCookieStorage (IVPrivate)
- (instancetype)initWithStorageLocation:(NSURL *)location;
@end

static IMP orig_sharedHTTPCookieStorage;
static id hooked_sharedHTTPCookieStorage(id self, SEL _cmd) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *path = active.cookiePath;
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSURL *loc = [NSURL fileURLWithPath:path isDirectory:YES];
        return [[NSHTTPCookieStorage alloc] initWithStorageLocation:loc];
    }
    return ((id(*)(id, SEL))orig_sharedHTTPCookieStorage)(self, _cmd);
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

    NSLog(@"[InstaVault] NSHTTPCookieStorage hook installed");
}
