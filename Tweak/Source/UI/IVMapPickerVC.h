#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Interactive MapKit location picker (plan-directeur §6): search bar
/// (MKLocalSearchCompleter/MKLocalSearch), long-press to drop a draggable pin,
/// reverse-geocode to "City, Country", and a high-contrast "Activate" commit
/// button. On commit, writes {lat,lng,name} to the container via the store.
@interface IVMapPickerVC : UIViewController

- (instancetype)initWithContainer:(IVContainer *)container;

/// Called after the coordinate is committed to the container.
@property (nonatomic, copy, nullable) void (^onCommit)(CLLocationCoordinate2D coord, NSString *name);

@end

NS_ASSUME_NONNULL_END
