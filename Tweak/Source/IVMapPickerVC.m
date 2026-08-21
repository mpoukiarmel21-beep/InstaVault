#import "IVMapPickerVC.h"
#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>

@interface IVMapPickerVC () <MKMapViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) UILabel *coords;
@property (nonatomic, strong) UIButton *btn;
@property (nonatomic, strong) MKPointAnnotation *pin;
@end

@implementation IVMapPickerVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Pick Location";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone
                                                                              target:self action:@selector(confirm)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    // Search bar
    _search = [UISearchBar new];
    _search.placeholder = @"Search city or address...";
    _search.delegate = self;
    _search.searchBarStyle = UISearchBarStyleMinimal;
    _search.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_search];

    // Map
    _map = [MKMapView new];
    _map.delegate = self;
    _map.showsUserLocation = YES;
    _map.userTrackingMode = MKUserTrackingModeFollow;
    _map.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_map];

    // Coordinates label
    _coords = [UILabel new];
    _coords.textAlignment = NSTextAlignmentCenter;
    _coords.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _coords.textColor = [UIColor secondaryLabelColor];
    _coords.text = @"Tap map or search to select location";
    _coords.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_coords];

    // Bottom confirm button
    _btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_btn setTitle:@"Confirm Location" forState:UIControlStateNormal];
    _btn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btn.backgroundColor = [UIColor systemBlueColor];
    _btn.layer.cornerRadius = 14;
    [_btn addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    _btn.enabled = NO;
    _btn.alpha = 0.5;
    _btn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_btn];

    [NSLayoutConstraint activateConstraints:@[
        [_search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_map.topAnchor constraintEqualToAnchor:_search.bottomAnchor],
        [_map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_map.bottomAnchor constraintEqualToAnchor:_coords.topAnchor constant:-12],
        [_coords.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_coords.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_coords.bottomAnchor constraintEqualToAnchor:_btn.topAnchor constant:-16],
        [_btn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_btn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_btn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [_btn.heightAnchor constraintEqualToConstant:54]
    ]];

    // Start at user location or Paris default
    CLLocationCoordinate2D start = CLLocationCoordinate2DMake(48.8566, 2.3522);
    [_map setRegion:MKCoordinateRegionMake(start, MKCoordinateSpanMake(0.5, 0.5)) animated:NO];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [_map addGestureRecognizer:tap];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)tapped:(UITapGestureRecognizer *)g {
    CGPoint pt = [g locationInView:_map];
    CLLocationCoordinate2D c = [_map convertPoint:pt toCoordinateFromView:_map];
    if (_pin) [_map removeAnnotation:_pin];
    _pin = [MKPointAnnotation new];
    _pin.coordinate = c;
    _pin.title = @"Selected";
    [_map addAnnotation:_pin];
    _coords.text = [NSString stringWithFormat:@"Lat: %.6f  Lon: %.6f", c.latitude, c.longitude];
    _btn.enabled = YES;
    _btn.alpha = 1.0;
}

- (void)confirm {
    if (!_pin) return;
    CLGeocoder *g = [CLGeocoder new];
    CLLocation *l = [[CLLocation alloc] initWithLatitude:_pin.coordinate.latitude longitude:_pin.coordinate.longitude];
    [g reverseGeocodeLocation:l completionHandler:^(NSArray<CLPlacemark *> *p, NSError *e) {
        NSString *n = @"Custom";
        if (p.count) {
            CLPlacemark *pm = p.firstObject;
            NSMutableArray *a = [NSMutableArray new];
            if (pm.locality) [a addObject:pm.locality];
            if (pm.administrativeArea) [a addObject:pm.administrativeArea];
            if (pm.country) [a addObject:pm.country];
            if (a.count) n = [a componentsJoinedByString:@", "];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.onPick) self.onPick(_pin.coordinate, n);
            [self.navigationController popViewControllerAnimated:YES];
        });
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)sb {
    [sb resignFirstResponder];
    if (!sb.text.length) return;
    CLGeocoder *g = [CLGeocoder new];
    [g geocodeAddressString:sb.text completionHandler:^(NSArray<CLPlacemark *> *p, NSError *e) {
        if (e || !p.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Not Found" message:nil preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            });
            return;
        }
        CLLocationCoordinate2D c = p.firstObject.location.coordinate;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_map setRegion:MKCoordinateRegionMake(c, MKCoordinateSpanMake(0.02, 0.02)) animated:YES];
            if (_pin) [_map removeAnnotation:_pin];
            _pin = [MKPointAnnotation new];
            _pin.coordinate = c;
            _pin.title = sb.text;
            [_map addAnnotation:_pin];
            _coords.text = [NSString stringWithFormat:@"Lat: %.6f  Lon: %.6f", c.latitude, c.longitude];
            _btn.enabled = YES;
            _btn.alpha = 1.0;
        });
    }];
}

- (MKAnnotationView *)mapView:(MKMapView *)mv viewForAnnotation:(id<MKAnnotation>)a {
    if ([a isKindOfClass:[MKUserLocation class]]) return nil;
    MKMarkerAnnotationView *v = [[MKMarkerAnnotationView alloc] initWithAnnotation:a reuseIdentifier:@"pin"];
    v.markerTintColor = [UIColor systemRedColor];
    v.glyphText = @"📍";
    v.animatesWhenAdded = YES;
    v.canShowCallout = YES;
    return v;
}

@end