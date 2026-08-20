#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static NSArray *sSchemes() {
    return @[@"cydia://", @"sileo://", @"zbra://", @"filza://", @"activator://"];
}

static BOOL isJailbreakURL(NSString *url) {
    for (NSString *sc in sSchemes()) {
        if ([url hasPrefix:sc]) return YES;
    }
    return NO;
}

#pragma mark - UIApplication hooks (safe ObjC swizzling)

typedef BOOL (*origCanOpenFunc)(id, SEL, NSURL *);

static origCanOpenFunc orig_canOpen = NULL;

static BOOL hook_canOpen(id self, SEL _cmd, NSURL *u) {
    NSString *s = [u absoluteString];
    if (isJailbreakURL(s)) return NO;
    return orig_canOpen(self, _cmd, u);
}

__attribute__((constructor))
static void initAntiDetect() {
    Class appClass = objc_getClass("UIApplication");
    if (appClass) {
        Method m3 = class_getInstanceMethod(appClass, @selector(canOpenURL:));
        if (m3) {
            orig_canOpen = (origCanOpenFunc)method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hook_canOpen);
        }
    }
    NSLog(@"[InstaVault] AntiDetect hook installed (ObjC only)");
}
