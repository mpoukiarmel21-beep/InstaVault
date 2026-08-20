#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "IVContainer.h"
#import "IVContainerManager.h"

static id (*orig_initWithSuiteName)(id, SEL, NSString *) = NULL;
static NSUserDefaults *(*orig_standardUserDefaults)(id, SEL) = NULL;

static id hook_initWithSuiteName(id self, SEL _cmd, NSString *s) {
    IVContainer *a = [IVContainerManager shared].active;
    if (a && s) return orig_initWithSuiteName(self, _cmd, [NSString stringWithFormat:@"%@_%@", s, a.cid]);
    return orig_initWithSuiteName(self, _cmd, s);
}

static NSUserDefaults *hook_standardUserDefaults(id self, SEL _cmd) {
    IVContainer *a = [IVContainerManager shared].active;
    if (a) return [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"com.ig.%@", a.cid]];
    return orig_standardUserDefaults(self, _cmd);
}

__attribute__((constructor))
static void initUserDefaultsHook() {
    Class cls = objc_getClass("NSUserDefaults");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(initWithSuiteName:));
        if (m1) {
            orig_initWithSuiteName = (id(*)(id, SEL, NSString *))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_initWithSuiteName);
        }
        Method m2 = class_getClassMethod(cls, @selector(standardUserDefaults));
        if (m2) {
            orig_standardUserDefaults = (NSUserDefaults *(*)(id, SEL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_standardUserDefaults);
        }
    }
    NSLog(@"[InstaVault] UserDefaults hook installed");
}