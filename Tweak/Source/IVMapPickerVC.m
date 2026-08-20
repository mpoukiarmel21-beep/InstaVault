#import "IVMapPickerVC.h"
#import <MapKit/MapKit.h>

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
    self.title=@"Pick Location"; self.view.backgroundColor=UIColor.systemBackgroundColor;

    self.search=[UISearchBar new]; self.search.placeholder=@"Search city..."; self.search.delegate=self;
    self.search.searchBarStyle=UISearchBarStyleMinimal; self.search.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.search];

    self.map=[MKMapView new]; self.map.delegate=self; self.map.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:self.map];

    self.coords=[UILabel new]; self.coords.textAlignment=NSTextAlignmentCenter;
    self.coords.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.coords.textColor=UIColor.secondaryLabelColor; self.coords.text=@"Tap map to place pin";
    self.coords.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.coords];

    self.btn=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.btn setTitle:@"Confirm" forState:UIControlStateNormal];
    self.btn.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.btn.backgroundColor=UIColor.systemBlueColor; [self.btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.btn.layer.cornerRadius=12; [self.btn addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    self.btn.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:self.btn];

    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.map.topAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.map.bottomAnchor constraintEqualToAnchor:self.coords.topAnchor constant:-8],
        [self.coords.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.coords.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.coords.bottomAnchor constraintEqualToAnchor:self.btn.topAnchor constant:-12],
        [self.btn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.btn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.btn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [self.btn.heightAnchor constraintEqualToConstant:50],
    ]];

    [self.map setRegion:MKCoordinateRegionMake(CLLocationCoordinate2DMake(48.8566,2.3522),MKCoordinateSpanMake(0.15,0.15)) animated:NO];

    UITapGestureRecognizer *t=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    [self.map addGestureRecognizer:t];
}
- (void)tapped:(UITapGestureRecognizer *)g {
    CGPoint pt=[g locationInView:self.map];
    CLLocationCoordinate2D c=[self.map convertPoint:pt toCoordinateFromView:self.map];
    if(self.pin)[self.map removeAnnotation:self.pin];
    self.pin=[MKPointAnnotation new]; self.pin.coordinate=c; self.pin.title=@"Selected";
    [self.map addAnnotation:self.pin];
    self.coords.text=[NSString stringWithFormat:@"Lat: %.6f  Lon: %.6f",c.latitude,c.longitude];
}
- (void)confirm {
    if(!self.pin){ UIAlertController *a=[UIAlertController alertControllerWithTitle:@"No pin" message:@"Tap map first" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; return; }
    CLGeocoder *g=[CLGeocoder new];
    CLLocation *l=[[CLLocation alloc] initWithLatitude:self.pin.coordinate.latitude longitude:self.pin.coordinate.longitude];
    [g reverseGeocodeLocation:l completionHandler:^(NSArray<CLPlacemark *> *p,NSError *e){
        NSString *n=@"Custom"; if(p.count){CLPlacemark *pm=p.firstObject;NSMutableArray *a=[NSMutableArray new];
        if(pm.locality)[a addObject:pm.locality];if(pm.country)[a addObject:pm.country];if(a.count)n=[a componentsJoinedByString:@", "];}
        dispatch_async(dispatch_get_main_queue(),^{if(self.onPick)self.onPick(self.pin.coordinate,n);[self.navigationController popViewControllerAnimated:YES];});
    }];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb {
    [sb resignFirstResponder]; if(!sb.text.length)return;
    CLGeocoder *g=[CLGeocoder new];
    [g geocodeAddressString:sb.text completionHandler:^(NSArray<CLPlacemark *> *p,NSError *e){
        if(e||!p.count){dispatch_async(dispatch_get_main_queue(),^{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Not found" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil];});return;}
        CLLocationCoordinate2D c=p.firstObject.location.coordinate;
        dispatch_async(dispatch_get_main_queue(),^{[self.map setRegion:MKCoordinateRegionMake(c,MKCoordinateSpanMake(0.01,0.01)) animated:YES];
        if(self.pin)[self.map removeAnnotation:self.pin]; self.pin=[MKPointAnnotation new];self.pin.coordinate=c;self.pin.title=sb.text;[self.map addAnnotation:self.pin];
        self.coords.text=[NSString stringWithFormat:@"Lat: %.6f  Lon: %.6f",c.latitude,c.longitude];});
    }];
}
- (MKAnnotationView *)mapView:(MKMapView *)mv viewForAnnotation:(id<MKAnnotation>)a {
    if([a isKindOfClass:[MKUserLocation class]])return nil;
    MKPinAnnotationView *p=[[MKPinAnnotationView alloc] initWithAnnotation:a reuseIdentifier:@"p"];
    p.animatesDrop=YES; p.canShowCallout=YES; p.pinColor=MKPinAnnotationColorRed; return p;
}
@end
