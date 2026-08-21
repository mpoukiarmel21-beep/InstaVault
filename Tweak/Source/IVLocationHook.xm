#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreLocation/CoreLocation.h>
#import "IVLocationSpoofing.h"

static IMP orig_location;
static CLLocation *hooked_location(id self, SEL _cmd) {
    IVLocationSpoofing *sp = [IVLocationSpoofing shared];
    if (sp.on) return sp.fake;
    return ((CLLocation *(*)(id, SEL))orig_location)(self, _cmd);
}

static IMP orig_startUpdatingLocation;
static void hooked_startUpdatingLocation(id self, SEL _cmd) {
    IVLocationSpoofing *sp = [IVLocationSpoofing shared];
    if (sp.on) {
        CLLocation *fake = sp.fake;
        id delegate = ((id(*)(id, SEL))objc_msgSend)(self, @selector(delegate));
        if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            NSArray *locs = @[fake];
            dispatch_async(dispatch_get_main_queue(), ^{
                ((void(*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(locationManager:didUpdateLocations:), self, locs);
            });
        }
        return;
    }
    ((void(*)(id, SEL))orig_startUpdatingLocation)(self, _cmd);
}

static IMP orig_requestLocation;
static void hooked_requestLocation(id self, SEL _cmd) {
    IVLocationSpoofing *sp = [IVLocationSpoofing shared];
    if (sp.on) {
        CLLocation *fake = sp.fake;
        id delegate = ((id(*)(id, SEL))objc_msgSend)(self, @selector(delegate));
        if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            NSArray *locs = @[fake];
            dispatch_async(dispatch_get_main_queue(), ^{
                ((void(*)(id, SEL, id, id))objc_msgSend)(delegate, @selector(locationManager:didUpdateLocations:), self, locs);
            });
        }
        return;
    }
    ((void(*)(id, SEL))orig_requestLocation)(self, _cmd);
}

__attribute__((constructor))
static void IVInstallLocationHook(void) {
    Class clm = objc_getClass("CLLocationManager");
    if (!clm) return;

    Method m_location = class_getInstanceMethod(clm, @selector(location));
    if (m_location) {
        orig_location = method_getImplementation(m_location);
        method_setImplementation(m_location, (IMP)hooked_location);
    }

    Method m_start = class_getInstanceMethod(clm, @selector(startUpdatingLocation));
    if (m_start) {
        orig_startUpdatingLocation = method_getImplementation(m_start);
        method_setImplementation(m_start, (IMP)hooked_startUpdatingLocation);
    }

    Method m_request = class_getInstanceMethod(clm, @selector(requestLocation));
    if (m_request) {
        orig_requestLocation = method_getImplementation(m_request);
        method_setImplementation(m_request, (IMP)hooked_requestLocation);
    }

    NSLog(@"[InstaVault] CLLocationManager hooks installed");
}
