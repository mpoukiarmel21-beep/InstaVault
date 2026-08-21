#import <Foundation/Foundation.h>
#import <AdSupport/AdSupport.h>
#import "IVDeviceSpoofing.h"

// IDFV (identifierForVendor) and IDFA (advertisingIdentifier) spoofing

static IMP orig_idfv;
static NSString *hooked_idfv(id self, SEL _cmd) {
    IVDeviceSpoofing *sp = [IVDeviceSpoofing shared];
    if (sp.on && sp.dev.idfv) return sp.dev.idfv;
    return ((NSString *(*)(id, SEL))orig_idfv)(self, _cmd);
}

static IMP orig_idfa;
static NSString *hooked_idfa(id self, SEL _cmd) {
    IVDeviceSpoofing *sp = [IVDeviceSpoofing shared];
    if (sp.on && sp.dev.idfa) return sp.dev.idfa;
    return ((NSString *(*)(id, SEL))orig_idfa)(self, _cmd);
}

__attribute__((constructor))
static void IVInstallIdentifierHook(void) {
    Class uidd = objc_getClass("UIDevice");
    if (uidd) {
        Method m_idfv = class_getInstanceMethod(uidd, @selector(identifierForVendor));
        if (m_idfv) {
            orig_idfv = method_getImplementation(m_idfv);
            method_setImplementation(m_idfv, (IMP)hooked_idfv);
        }
    }

    Class as = objc_getClass("ASIdentifierManager");
    if (as) {
        Method m_shared = class_getClassMethod(as, @selector(sharedManager));
        if (m_shared) {
            // We can't easily hook the class method's return value,
            // so hook the instance method advertisingIdentifier
            Method m_idfa = class_getInstanceMethod(as, @selector(advertisingIdentifier));
            if (m_idfa) {
                orig_idfa = method_getImplementation(m_idfa);
                method_setImplementation(m_idfa, (IMP)hooked_idfa);
            }
        }
    }

    NSLog(@"[InstaVault] IDFV/IDFA hooks installed");
}