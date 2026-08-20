#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
@interface IVLocationSpoofing : NSObject
@property (nonatomic, assign) BOOL on;
@property (nonatomic, assign) CLLocationCoordinate2D coord;
+ (instancetype)shared;
- (void)enable:(CLLocationCoordinate2D)c;
- (void)disable;
- (CLLocation *)fake;
@end
