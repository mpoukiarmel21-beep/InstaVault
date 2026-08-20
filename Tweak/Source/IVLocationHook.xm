#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "IVContainer.h"
#import "IVContainerManager.h"
#import "IVLocationSpoofing.h"
%hook CLLocationManager
- (void)startUpdatingLocation {
    IVContainer *a=[IVContainerManager shared].active;
    if(a&&[a hasLocation]){
        IVLocationSpoofing *s=[IVLocationSpoofing shared]; [s enable:a.location];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)])
                [self.delegate locationManager:self didUpdateLocations:@[[s fake]]];
        });
    } else %orig;
}
- (CLLocation *)location {
    IVLocationSpoofing *s=[IVLocationSpoofing shared];
    if(s.on)return [s fake]; return %orig;
}
- (void)requestLocation {
    IVContainer *a=[IVContainerManager shared].active;
    if(a&&[a hasLocation]){
        IVLocationSpoofing *s=[IVLocationSpoofing shared]; [s enable:a.location];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            if([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)])
                [self.delegate locationManager:self didUpdateLocations:@[[s fake]]];
        });
    } else %orig;
}
%end
