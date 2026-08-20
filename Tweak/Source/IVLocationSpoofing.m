#import "IVLocationSpoofing.h"
@implementation IVLocationSpoofing
+ (instancetype)shared { static IVLocationSpoofing *i; static dispatch_once_t o; dispatch_once(&o, ^{ i=[self new]; }); return i; }
- (void)enable:(CLLocationCoordinate2D)c { self.coord=c; self.on=YES; }
- (void)disable { self.on=NO; self.coord=CLLocationCoordinate2DMake(0,0); }
- (CLLocation *)fake {
    return [[CLLocation alloc] initWithCoordinate:self.coord
        altitude:10+arc4random_uniform(100) horizontalAccuracy:kCLLocationAccuracyBest
        verticalAccuracy:5+arc4random_uniform(10) course:arc4random_uniform(360)
        speed:0.5+arc4random_uniform(10)/10.0 timestamp:[NSDate date]];
}
@end
