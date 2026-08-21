#import <Foundation/Foundation.h>
#import "IVContainerManager.h"

// Per-container NSUserDefaults isolation

static IMP orig_standardUserDefaults;
static id hooked_standardUserDefaults(id self, SEL _cmd) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *path = active.sandbox;
        NSString *plist = [path stringByAppendingPathComponent:@"Library/Preferences/com.burbn.instagram.plist"];
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:active.cid];
        if (!ud) ud = [[NSUserDefaults alloc] init];
        // Force reading/writing to container's prefs
        [ud addSuiteNamed:[NSString stringWithFormat:@"InstaVault.%@", active.cid]];
        return ud;
    }
    return ((id(*)(id, SEL))orig_standardUserDefaults)(self, _cmd);
}

static IMP orig_initWithSuiteName;
static id hooked_initWithSuiteName(id self, SEL _cmd, NSString *suiteName) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *containerSuite = [NSString stringWithFormat:@"InstaVault.%@", active.cid];
        return ((id(*)(id, SEL, NSString *))orig_initWithSuiteName)(self, _cmd, containerSuite);
    }
    return ((id(*)(id, SEL, NSString *))orig_initWithSuiteName)(self, _cmd, suiteName);
}

static IMP orig_objectForKey;
static id hooked_objectForKey(id self, SEL _cmd, NSString *key) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *containerSuite = [NSString stringWithFormat:@"InstaVault.%@", active.cid];
        NSUserDefaults *containerUD = [[NSUserDefaults alloc] initWithSuiteName:containerSuite];
        if (containerUD) return [containerUD objectForKey:key];
    }
    return ((id(*)(id, SEL, NSString *))orig_objectForKey)(self, _cmd, key);
}

static IMP orig_setObject;
static void hooked_setObject(id self, SEL _cmd, id value, NSString *key) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) {
        NSString *containerSuite = [NSString stringWithFormat:@"InstaVault.%@", active.cid];
        NSUserDefaults *containerUD = [[NSUserDefaults alloc] initWithSuiteName:containerSuite];
        if (containerUD) {
            [containerUD setObject:value forKey:key];
            [containerUD synchronize];
            return;
        }
    }
    ((void(*)(id, SEL, id, NSString *))orig_setObject)(self, _cmd, value, key);
}

__attribute__((constructor))
static void IVInstallUserDefaultsHook(void) {
    Class ud = objc_getClass("NSUserDefaults");
    if (!ud) return;

    Method m_standard = class_getClassMethod(ud, @selector(standardUserDefaults));
    if (m_standard) {
        orig_standardUserDefaults = method_getImplementation(m_standard);
        method_setImplementation(m_standard, (IMP)hooked_standardUserDefaults);
    }

    Method m_init = class_getInstanceMethod(ud, @selector(initWithSuiteName:));
    if (m_init) {
        orig_initWithSuiteName = method_getImplementation(m_init);
        method_setImplementation(m_init, (IMP)hooked_initWithSuiteName);
    }

    Method m_get = class_getInstanceMethod(ud, @selector(objectForKey:));
    if (m_get) {
        orig_objectForKey = method_getImplementation(m_get);
        method_setImplementation(m_get, (IMP)hooked_objectForKey);
    }

    Method m_set = class_getInstanceMethod(ud, @selector(setObject:forKey:));
    if (m_set) {
        orig_setObject = method_getImplementation(m_set);
        method_setImplementation(m_set, (IMP)hooked_setObject);
    }

    NSLog(@"[InstaVault] NSUserDefaults hooks installed");
}