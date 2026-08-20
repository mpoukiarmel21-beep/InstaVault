#import <Foundation/Foundation.h>
#import <AdSupport/AdSupport.h>
#import <objc/runtime.h>
#import "IVContainer.h"
#import "IVContainerManager.h"
#import "IVFakeDevice.h"

static NSUUID *(*orig_advertisingIdentifier)(id, SEL) = NULL;
static BOOL (*orig_isAdvertisingTrackingEnabled)(id, SEL) = NULL;

static NSUUID *hook_advertisingIdentifier(id self, SEL _cmd) {
    IVContainer *a = [IVContainerManager shared].active;
    if (a && a.device) return [[NSUUID alloc] initWithUUIDString:a.device.idfa];
    return orig_advertisingIdentifier(self, _cmd);
}

static BOOL hook_isAdvertisingTrackingEnabled(id self, SEL _cmd) {
    return YES;
}

__attribute__((constructor))
static void initIdentifierHook() {
    Class cls = objc_getClass("ASIdentifierManager");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(advertisingIdentifier));
        if (m1) {
            orig_advertisingIdentifier = (NSUUID *(*)(id, SEL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_advertisingIdentifier);
        }
        Method m2 = class_getInstanceMethod(cls, @selector(isAdvertisingTrackingEnabled));
        if (m2) {
            orig_isAdvertisingTrackingEnabled = (BOOL(*)(id, SEL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_isAdvertisingTrackingEnabled);
        }
    }
    NSLog(@"[InstaVault] Identifier hook installed");
}