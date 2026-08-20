#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import "IVContainer.h"
#import "IVContainerManager.h"
#import "IVLocationSpoofing.h"

static void (*orig_startUpdatingLocation)(id, SEL) = NULL;
static CLLocation *(*orig_location)(id, SEL) = NULL;
static void (*orig_requestLocation)(id, SEL) = NULL;

static void IVFeedDelegate(id self) {
    IVContainer *a = [IVContainerManager shared].active;
    if (!a || ![a hasLocation]) return;
    IVLocationSpoofing *s = [IVLocationSpoofing shared];
    [s enable:a.location];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)])
            [self.delegate locationManager:self didUpdateLocations:@[[s fake]]];
    });
}

static void hook_startUpdatingLocation(id self, SEL _cmd) {
    IVContainer *a = [IVContainerManager shared].active;
    if (a && [a hasLocation]) {
        IVFeedDelegate(self);
    } else {
        orig_startUpdatingLocation(self, _cmd);
    }
}

static CLLocation *hook_location(id self, SEL _cmd) {
    IVLocationSpoofing *s = [IVLocationSpoofing shared];
    if (s.on) return [s fake];
    return orig_location(self, _cmd);
}

static void hook_requestLocation(id self, SEL _cmd) {
    IVContainer *a = [IVContainerManager shared].active;
    if (a && [a hasLocation]) {
        IVFeedDelegate(self);
    } else {
        orig_requestLocation(self, _cmd);
    }
}

__attribute__((constructor))
static void initLocationHook() {
    Class cls = objc_getClass("CLLocationManager");
    if (cls) {
        Method m1 = class_getInstanceMethod(cls, @selector(startUpdatingLocation));
        if (m1) {
            orig_startUpdatingLocation = (void(*)(id, SEL))method_getImplementation(m1);
            method_setImplementation(m1, (IMP)hook_startUpdatingLocation);
        }
        Method m2 = class_getInstanceMethod(cls, @selector(location));
        if (m2) {
            orig_location = (CLLocation *(*)(id, SEL))method_getImplementation(m2);
            method_setImplementation(m2, (IMP)hook_location);
        }
        Method m3 = class_getInstanceMethod(cls, @selector(requestLocation));
        if (m3) {
            orig_requestLocation = (void(*)(id, SEL))method_getImplementation(m3);
            method_setImplementation(m3, (IMP)hook_requestLocation);
        }
    }
    NSLog(@"[InstaVault] Location hook installed");
}