#import "IVMapPickerVC.h"
#import "IVTheme.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import <MapKit/MapKit.h>

@interface IVMapPickerVC () <MKMapViewDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) IVContainer *container;
@property (nonatomic, strong) MKMapView *map;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) UIButton *commit;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) CLGeocoder *geocoder;
@property (nonatomic, assign) CLLocationCoordinate2D chosen;
@property (nonatomic, copy, nullable) NSString *chosenName;
@end

@implementation IVMapPickerVC

- (instancetype)initWithContainer:(IVContainer *)container {
    if ((self = [super init])) {
        _container = container;
        _geocoder = [CLGeocoder new];
        _chosen = kCLLocationCoordinate2DInvalid;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Localisation GPS";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.search = [UISearchBar new];
    self.search.translatesAutoresizingMaskIntoConstraints = NO;
    self.search.placeholder = @"Rechercher une ville…";
    self.search.delegate = self;
    self.search.searchBarStyle = UISearchBarStyleMinimal;

    self.map = [MKMapView new];
    self.map.translatesAutoresizingMaskIntoConstraints = NO;
    self.map.delegate = self;
    self.map.showsUserLocation = NO;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
                                        initWithTarget:self action:@selector(onLongPress:)];
    // Don't let a long-press on the existing pin drop/relocate it — that touch
    // belongs to MapKit's pin drag. Only bare-map long-presses drop a new pin.
    lp.delegate = self;
    [self.map addGestureRecognizer:lp];

    self.commit = [UIButton buttonWithType:UIButtonTypeSystem];
    self.commit.translatesAutoresizingMaskIntoConstraints = NO;
    [self.commit setTitle:@"Activer cette position" forState:UIControlStateNormal];
    [self.commit setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    // White on the accent violet clears AA for large text (≥18pt bold, 3:1);
    // the accent is deeper than systemPurple so contrast is a touch better still.
    UIFont *commitFont = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.commit.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
                                   scaledFontForFont:commitFont];
    self.commit.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.commit.backgroundColor = IVTheme.accent;
    self.commit.layer.cornerRadius = 14;
    self.commit.layer.cornerCurve = kCACornerCurveContinuous;
    [self.commit addTarget:self action:@selector(doCommit) forControlEvents:UIControlEventTouchUpInside];

    // A "Clear" button to remove the fake location entirely.
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Effacer" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(clearLocation)];

    [self.view addSubview:self.search];
    [self.view addSubview:self.map];
    [self.view addSubview:self.commit];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.search.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],

        [self.map.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:4],
        [self.map.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.map.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.map.bottomAnchor constraintEqualToAnchor:self.commit.topAnchor constant:-12],

        [self.commit.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.commit.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [self.commit.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
        [self.commit.heightAnchor constraintEqualToConstant:52],
    ]];

    [self loadInitial];
}

#pragma mark - Initial state

- (void)loadInitial {
    if (self.container.hasLocation) {
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake(self.container.latitude.doubleValue,
                                                              self.container.longitude.doubleValue);
        self.chosenName = self.container.locationName;
        [self setChosen:c reverseGeocode:NO];
        [self.map setRegion:MKCoordinateRegionMakeWithDistance(c, 4000, 4000) animated:NO];
    } else {
        // Default view: Paris, so the map isn't blank mid-ocean.
        [self.map setRegion:MKCoordinateRegionMakeWithDistance(CLLocationCoordinate2DMake(48.8566, 2.3522),
                                                               200000, 200000) animated:NO];
    }
    [self refreshCommitState];
}

- (void)refreshCommitState {
    BOOL valid = CLLocationCoordinate2DIsValid(self.chosen);
    self.commit.enabled = valid;
    self.commit.alpha = valid ? 1.0 : 0.4;
}

#pragma mark - Choosing a point

- (void)setChosen:(CLLocationCoordinate2D)coord reverseGeocode:(BOOL)geocode {
    self.chosen = coord;
    if (!self.pin) {
        self.pin = [MKPointAnnotation new];
        [self.map addAnnotation:self.pin];
    }
    self.pin.coordinate = coord;
    self.pin.title = self.chosenName ?: @"Position choisie";
    [self.map setCenterCoordinate:coord animated:YES];
    [self refreshCommitState];

    if (!geocode) return;
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    __weak typeof(self) ws = self;
    [self.geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *marks, NSError *err) {
        CLPlacemark *p = marks.firstObject;
        if (!p) return;
        NSString *city = p.locality ?: p.name ?: @"";
        NSString *country = p.country ?: @"";
        NSString *name = country.length ? [NSString stringWithFormat:@"%@, %@", city, country] : city;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) ss = ws;
            if (!ss) return;
            ss.chosenName = name;
            ss.pin.title = name;
        });
    }];
}

- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [g locationInView:self.map];
    CLLocationCoordinate2D coord = [self.map convertPoint:pt toCoordinateFromView:self.map];
    self.chosenName = nil;
    [self setChosen:coord reverseGeocode:YES];
}

// Ignore long-presses that land on an annotation view (the pin) so grabbing the
// pin drags it (MapKit) instead of dropping a second pin underneath.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    UIView *v = touch.view;
    while (v) {
        if ([v isKindOfClass:[MKAnnotationView class]]) return NO;
        v = v.superview;
    }
    return YES;
}

#pragma mark - Search

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *q = searchBar.text;
    if (q.length == 0) return;

    MKLocalSearchRequest *req = [MKLocalSearchRequest new];
    req.naturalLanguageQuery = q;
    req.region = self.map.region;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:req];
    __weak typeof(self) ws = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *resp, NSError *err) {
        MKMapItem *item = resp.mapItems.firstObject;
        if (!item) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(ws) ss = ws;
            if (!ss) return;
            ss.chosenName = item.name ?: item.placemark.locality;
            [ss setChosen:item.placemark.coordinate reverseGeocode:YES];
            [ss.map setRegion:MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 6000, 6000) animated:YES];
        });
    }];
}

#pragma mark - Map delegate (draggable pin)

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    MKMarkerAnnotationView *v = (MKMarkerAnnotationView *)
        [mapView dequeueReusableAnnotationViewWithIdentifier:@"p"];
    if (!v) {
        v = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"p"];
        v.markerTintColor = IVTheme.accent;
        v.canShowCallout = YES;
    }
    v.annotation = annotation;
    v.draggable = YES;
    return v;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view
    didChangeDragState:(MKAnnotationViewDragState)newState
          fromOldState:(MKAnnotationViewDragState)oldState {
    if (newState == MKAnnotationViewDragStateEnding) {
        self.chosenName = nil;
        [self setChosen:view.annotation.coordinate reverseGeocode:YES];
    }
}

#pragma mark - Commit / clear

- (void)doCommit {
    if (!CLLocationCoordinate2DIsValid(self.chosen)) return;
    BOOL ok = [[IVContainerStore shared] setLocation:@(self.chosen.latitude)
                                                 lng:@(self.chosen.longitude)
                                                name:self.chosenName
                                        forContainer:self.container];
    if (!ok) { [self warnLocationSaveFailed]; return; }
    if (self.onCommit) self.onCommit(self.chosen, self.chosenName ?: @"");
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)clearLocation {
    if (![[IVContainerStore shared] setLocation:nil lng:nil name:nil forContainer:self.container]) {
        [self warnLocationSaveFailed];
        return;
    }
    if (self.onCommit) self.onCommit(kCLLocationCoordinate2DInvalid, @"");
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)warnLocationSaveFailed {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Échec de l'enregistrement"
        message:@"La localisation n'a pas pu être enregistrée (écriture disque échouée). Réessaie."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
