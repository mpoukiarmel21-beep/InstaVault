#import "IVLocationSpoof.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Util/IVDiagnostics.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

#pragma mark - Current fake location (read live from the active container)

// Returns a freshly-synthesized CLLocation at the active container's coordinate,
// or nil when the active container has no location set (real location flows).
static CLLocation *IVCurrentFakeLocation(void) {
    IVContainer *c = [IVContainerStore shared].activeContainer;
    if (!c.hasLocation) return nil;

    CLLocationDegrees lat = c.latitude.doubleValue;
    CLLocationDegrees lng = c.longitude.doubleValue;

    // Sub-meter jitter so successive reads aren't byte-identical (looks alive).
    double jLat = ((double)arc4random_uniform(2000) - 1000.0) / 1.0e8;   // ±~1m
    double jLng = ((double)arc4random_uniform(2000) - 1000.0) / 1.0e8;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(lat + jLat, lng + jLng);

    return [[CLLocation alloc] initWithCoordinate:coord
                                         altitude:12.0
                               horizontalAccuracy:5.0
                                 verticalAccuracy:8.0
                                           course:-1
                                            speed:0
                                        timestamp:[NSDate date]];
}

// Saved originals.
static CLLocation *(*orig_location)(id, SEL) = NULL;
static void (*orig_start)(id, SEL) = NULL;
static void (*orig_stop)(id, SEL) = NULL;
static void (*orig_request)(id, SEL) = NULL;
static CLLocation *(*orig_update_location)(id, SEL) = NULL;
// Authorization surfaces (see the hooks in +install).
static CLAuthorizationStatus (*orig_auth_inst)(id, SEL) = NULL;   // -[CLLocationManager authorizationStatus] (iOS 14+)
static CLAuthorizationStatus (*orig_auth_cls)(id, SEL)  = NULL;   // +[CLLocationManager authorizationStatus] (deprecated)
static BOOL (*orig_services_enabled)(id, SEL) = NULL;             // +[CLLocationManager locationServicesEnabled]
static void (*orig_req_wheninuse)(id, SEL) = NULL;
static void (*orig_req_always)(id, SEL)    = NULL;
static BOOL gInstalled = NO;

// Per-manager associated state: the repeating reconcile timer, and whether WE
// have the real GPS running for this manager.
static const void *kIVFakeTimerKey = &kIVFakeTimerKey;
static const void *kIVRealOnKey = &kIVRealOnKey;

static BOOL IVRealOn(CLLocationManager *mgr) {
    return [objc_getAssociatedObject(mgr, kIVRealOnKey) boolValue];
}
static void IVSetRealOn(CLLocationManager *mgr, BOOL on) {
    objc_setAssociatedObject(mgr, kIVRealOnKey, @(on), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Deliver one fake fix to the manager's delegate. MUST be called on the main
// thread (the delegate contract expects main-thread callbacks). Reads the
// delegate live each time so a delegate set after -startUpdatingLocation still
// receives fixes.
static void IVDeliverFake(CLLocationManager *mgr) {
    CLLocation *fake = IVCurrentFakeLocation();
    if (!fake) return;
    id<CLLocationManagerDelegate> del = mgr.delegate;
    if ([del respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [del locationManager:mgr didUpdateLocations:@[ fake ]];
    }
}

// Tell a manager's delegate we're authorized (when-in-use). Called after the app
// requests permission WHILE faking: our -authorizationStatus hook already reports
// authorized, so we just nudge the delegate to (re)query and start streaming.
// Main-thread only, per the delegate contract.
static void IVNotifyAuthorized(CLLocationManager *mgr) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id<CLLocationManagerDelegate> del = mgr.delegate;
        if ([del respondsToSelector:@selector(locationManagerDidChangeAuthorization:)]) {
            [del locationManagerDidChangeAuthorization:mgr];              // iOS 14+
        }
        if ([del respondsToSelector:@selector(locationManager:didChangeAuthorizationStatus:)]) {
            [del locationManager:mgr didChangeAuthorizationStatus:kCLAuthorizationStatusAuthorizedWhenInUse];  // legacy
        }
    });
}

// Reconcile ONE streaming manager against the live active-container state. Main
// thread only. This is re-evaluated every tick, so toggling the active
// container's location mid-session takes effect within ~1s instead of being
// latched forever at -startUpdatingLocation:
//   • faking now  → make sure the real GPS is OFF (never leak the true fix) and
//                    push a synthetic fix to the delegate;
//   • not faking  → make sure the real GPS is ON so the delegate keeps getting
//                    genuine fixes (the tweak is transparent when no location
//                    is set for the active container).
static void IVReconcile(CLLocationManager *mgr) {
    if ([IVLocationSpoof isActive]) {
        if (IVRealOn(mgr) && orig_stop) {
            orig_stop(mgr, @selector(stopUpdatingLocation));
            IVSetRealOn(mgr, NO);
        }
        IVDeliverFake(mgr);
    } else {
        if (!IVRealOn(mgr) && orig_start) {
            orig_start(mgr, @selector(startUpdatingLocation));
            IVSetRealOn(mgr, YES);
        }
    }
}

// Tear down the reconcile stream for a manager and stop any real GPS we started.
static void IVStopStream(CLLocationManager *mgr) {
    NSTimer *t = objc_getAssociatedObject(mgr, kIVFakeTimerKey);
    if (t) {
        [t invalidate];
        objc_setAssociatedObject(mgr, kIVFakeTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    IVSetRealOn(mgr, NO);
    if (orig_stop) orig_stop(mgr, @selector(stopUpdatingLocation));
}

// Start (or restart) the reconcile stream for `mgr`. A 1s repeating timer keeps
// fake/real delivery in sync with the live active-container state (see
// IVReconcile). The timer captures the manager weakly (no retain cycle: mgr
// retains the timer via the associated object, not vice-versa); if the manager
// is deallocated without a -stopUpdatingLocation, the next tick sees nil and
// invalidates itself.
static void IVStartStream(CLLocationManager *mgr) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *old = objc_getAssociatedObject(mgr, kIVFakeTimerKey);
        if (old) [old invalidate];
        IVReconcile(mgr);   // immediate first reconcile
        __weak CLLocationManager *weakMgr = mgr;
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            CLLocationManager *m = weakMgr;
            if (!m) { [timer invalidate]; return; }
            IVReconcile(m);
        }];
        objc_setAssociatedObject(mgr, kIVFakeTimerKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark - Install

@implementation IVLocationSpoof

+ (void)install {
    if (gInstalled) return;
    gInstalled = YES;

    Class mgr = [CLLocationManager class];

    // -location getter: return the fake fix when active, else the real value.
    Method mLoc = class_getInstanceMethod(mgr, @selector(location));
    if (mLoc) {
        orig_location = (CLLocation *(*)(id, SEL))method_getImplementation(mLoc);
        method_setImplementation(mLoc, imp_implementationWithBlock(^CLLocation *(id _self) {
            CLLocation *fake = IVCurrentFakeLocation();
            return fake ?: orig_location(_self, @selector(location));
        }));
    }

    // -startUpdatingLocation: drive a reconciling stream. The fake-vs-real
    // decision is re-evaluated every tick (see IVReconcile), NOT latched here,
    // so enabling/clearing the active container's location mid-session is
    // honoured without the app having to restart location updates.
    Method mStart = class_getInstanceMethod(mgr, @selector(startUpdatingLocation));
    if (mStart) {
        orig_start = (void (*)(id, SEL))method_getImplementation(mStart);
        method_setImplementation(mStart, imp_implementationWithBlock(^(id _self) {
            IVStartStream(_self);
        }));
    }

    // -stopUpdatingLocation: tear down the reconcile stream and stop any real
    // GPS we started on the app's behalf.
    Method mStop = class_getInstanceMethod(mgr, @selector(stopUpdatingLocation));
    if (mStop) {
        orig_stop = (void (*)(id, SEL))method_getImplementation(mStop);
        method_setImplementation(mStop, imp_implementationWithBlock(^(id _self) {
            IVStopStream(_self);
        }));
    }

    // -requestLocation: one-shot. When faking, synthesize a single fix and never
    // touch the real GPS; otherwise defer to the real implementation.
    Method mReq = class_getInstanceMethod(mgr, @selector(requestLocation));
    if (mReq) {
        orig_request = (void (*)(id, SEL))method_getImplementation(mReq);
        method_setImplementation(mReq, imp_implementationWithBlock(^(id _self) {
            if ([IVLocationSpoof isActive]) {
                dispatch_async(dispatch_get_main_queue(), ^{ IVDeliverFake(_self); });
            } else {
                orig_request(_self, @selector(requestLocation));
            }
        }));
    }

    // iOS 17+ async path: -[CLLocationUpdate location].
    Class upd = NSClassFromString(@"CLLocationUpdate");
    Method mUpd = upd ? class_getInstanceMethod(upd, @selector(location)) : NULL;
    if (mUpd) {
        orig_update_location = (CLLocation *(*)(id, SEL))method_getImplementation(mUpd);
        method_setImplementation(mUpd, imp_implementationWithBlock(^CLLocation *(id _self) {
            CLLocation *fake = IVCurrentFakeLocation();
            return fake ?: orig_update_location(_self, @selector(location));
        }));
    }

    // Authorization surfaces. Without these, an app that has NOT been granted
    // location permission never calls -startUpdatingLocation, so our fake fix
    // would never surface (the #1 reason a spoofed location "doesn't show up").
    // When faking (active container has a location), report authorizedWhenInUse
    // + services-enabled so the app proceeds to query; otherwise pass through the
    // real status so the tweak stays transparent.

    // -[CLLocationManager authorizationStatus] — instance property, iOS 14+.
    Method mAuthI = class_getInstanceMethod(mgr, @selector(authorizationStatus));
    if (mAuthI) {
        orig_auth_inst = (CLAuthorizationStatus (*)(id, SEL))method_getImplementation(mAuthI);
        method_setImplementation(mAuthI, imp_implementationWithBlock(^CLAuthorizationStatus(id _self) {
            if ([IVLocationSpoof isActive]) return kCLAuthorizationStatusAuthorizedWhenInUse;
            return orig_auth_inst(_self, @selector(authorizationStatus));
        }));
    }

    // +[CLLocationManager authorizationStatus] — deprecated class method, still read.
    Method mAuthC = class_getClassMethod(mgr, @selector(authorizationStatus));
    if (mAuthC) {
        orig_auth_cls = (CLAuthorizationStatus (*)(id, SEL))method_getImplementation(mAuthC);
        method_setImplementation(mAuthC, imp_implementationWithBlock(^CLAuthorizationStatus(id _self) {
            if ([IVLocationSpoof isActive]) return kCLAuthorizationStatusAuthorizedWhenInUse;
            return orig_auth_cls(_self, @selector(authorizationStatus));
        }));
    }

    // +[CLLocationManager locationServicesEnabled].
    Method mSvc = class_getClassMethod(mgr, @selector(locationServicesEnabled));
    if (mSvc) {
        orig_services_enabled = (BOOL (*)(id, SEL))method_getImplementation(mSvc);
        method_setImplementation(mSvc, imp_implementationWithBlock(^BOOL(id _self) {
            if ([IVLocationSpoof isActive]) return YES;
            return orig_services_enabled(_self, @selector(locationServicesEnabled));
        }));
    }

    // -requestWhenInUseAuthorization / -requestAlwaysAuthorization: when faking,
    // don't prompt the real system — immediately tell the delegate we're
    // authorized so the app moves on to querying location.
    Method mReqW = class_getInstanceMethod(mgr, @selector(requestWhenInUseAuthorization));
    if (mReqW) {
        orig_req_wheninuse = (void (*)(id, SEL))method_getImplementation(mReqW);
        method_setImplementation(mReqW, imp_implementationWithBlock(^(id _self) {
            if ([IVLocationSpoof isActive]) IVNotifyAuthorized(_self);
            else orig_req_wheninuse(_self, @selector(requestWhenInUseAuthorization));
        }));
    }
    Method mReqA = class_getInstanceMethod(mgr, @selector(requestAlwaysAuthorization));
    if (mReqA) {
        orig_req_always = (void (*)(id, SEL))method_getImplementation(mReqA);
        method_setImplementation(mReqA, imp_implementationWithBlock(^(id _self) {
            if ([IVLocationSpoof isActive]) IVNotifyAuthorized(_self);
            else orig_req_always(_self, @selector(requestAlwaysAuthorization));
        }));
    }

    IVLog(@"LocationSpoof installed (getter/start/stop/request/update + authorization)");
}

+ (BOOL)isActive {
    return [IVContainerStore shared].activeContainer.hasLocation;
}

@end
