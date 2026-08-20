#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
typedef void(^IVPick)(CLLocationCoordinate2D coord,NSString *name);
@interface IVMapPickerVC : UIViewController
@property (nonatomic, copy) IVPick onPick;
@end
