#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "IVContainer.h"
#import "IVContainerManager.h"
#import "IVFakeDevice.h"

static NSMutableDictionary *cookieStorage = nil;

typedef NSHTTPCookieStorage *(*origCookieFunc)(id, SEL);
static origCookieFunc orig_sharedHTTPCookieStorage = NULL;

static NSHTTPCookieStorage *hook_sharedHTTPCookieStorage(id self, SEL _cmd) {
    IVContainer *a = [IVContainerManager shared].active;
    if (!a) return orig_sharedHTTPCookieStorage(self, _cmd);
    static dispatch_once_t o;
    dispatch_once(&o, ^{ cookieStorage = [NSMutableDictionary new]; });
    NSHTTPCookieStorage *s = cookieStorage[a.cid];
    if (!s) { s = orig_sharedHTTPCookieStorage(self, _cmd); cookieStorage[a.cid] = s; }
    return s;
}

typedef NSUUID *(*origIDFVFunc)(id, SEL);
static origIDFVFunc orig_identifierForVendor = NULL;

static NSUUID *hook_identifierForVendor(id self, SEL _cmd) {
    IVContainer *a = [IVContainerManager shared].active;
    if (a && a.device) return [[NSUUID alloc] initWithUUIDString:a.device.idfv];
    return orig_identifierForVendor(self, _cmd);
}

__attribute__((constructor))
static void initCookieHook() {
    Class cookieClass = [NSHTTPCookieStorage class];
    Method m1 = class_getClassMethod(cookieClass, @selector(sharedHTTPCookieStorage));
    orig_sharedHTTPCookieStorage = (origCookieFunc)method_getImplementation(m1);
    method_setImplementation(m1, (IMP)hook_sharedHTTPCookieStorage);

    Class devClass = [UIDevice class];
    Method m2 = class_getInstanceMethod(devClass, @selector(identifierForVendor));
    if (m2) {
        orig_identifierForVendor = (origIDFVFunc)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hook_identifierForVendor);
    }

    NSLog(@"[InstaVault] Cookie hook installed");
}
