#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "IVLocationSpoofing.h"

// Pure ObjC runtime swizzling for CLLocationManager to spoof GPS location

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
        // Fire delegate callback immediately with fake location
        id delegate = ((id(*)(id, SEL))class_getMethodImplementation([CLLocationManager class], @selector(delegate)))(self, @selector(delegate));
        if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [delegate performSelectorOnMainThread:@selector(locationManager:didUpdateLocations:)
                                       withObject:self
                                    withObject:@[sp.fake]
                                 waitUntilDone:NO];
        }
        return;
    }
    ((void(*)(id, SEL))orig_startUpdatingLocation)(self, _cmd);
}

static IMP orig_requestLocation;
static void hooked_requestLocation(id self, SEL _cmd) {
    IVLocationSpoofing *sp = [IVLocationSpoofing shared];
    if (sp.on) {
        id delegate = ((id(*)(id, SEL))class_getMethodImplementation([CLLocationManager class], @selector(delegate)))(self, @selector(delegate));
        if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            [delegate performSelectorOnMainThread:@selector(locationManager:didUpdateLocations:)
                                       withObject:self
                                    withObject:@[sp.fake]
                                 waitUntilDone:NO];
        }
        return;
    }
    ((void(*)(id, SEL))orig_requestLocation)(self, _cmd);
}

static IMP orig_desiredAccuracy;
static CLLocationAccuracy hooked_desiredAccuracy(id self, SEL _cmd) {
    IVLocationSpoofing *sp = [IVLocationSpoofing shared];
    if (sp.on) return kCLLocationAccuracyBest;
    return ((CLLocationAccuracy(*)(id, SEL))orig_desiredAccuracy)(self, _cmd);
}

__attribute__((constructor))
static void IVInstallLocationHook(void) {
    Class clm = objc_getClass("CLLocationManager");
    
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

    Method m_accuracy = class_getInstanceMethod(clm, @selector(desiredAccuracy));
    if (m_accuracy) {
        orig_desiredAccuracy = method_getImplementation(m_accuracy);
        method_setImplementation(m_accuracy, (IMP)hooked_desiredAccuracy);
    }

    NSLog(@"[InstaVault] CLLocationManager hooks installed");
}