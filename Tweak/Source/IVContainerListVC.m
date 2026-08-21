#import "IVContainerListVC.h"
#import "IVContainerCreateVC.h"
#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVFakeDevice.h"
#import "IVFloatingButton.h"
#import "IVThemeManager.h"
#import <UIKit/UIKit.h>

@interface IVContainerListVC () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) NSArray *items;
@end

@implementation IVContainerListVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"InstaVault Containers";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    // Navigation bar buttons
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self action:@selector(add)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(dismissSelf)];

    // Table
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    [_table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_table];

    // Empty state
    _emptyView = [self emptyStateView];
    _emptyView.frame = self.view.bounds;
    _emptyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_emptyView];

    [self refresh];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:kIVListChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:kIVActiveChanged object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    _items = [[IVContainerManager shared].list copy];
    _table.hidden = _items.count == 0;
    _emptyView.hidden = _items.count > 0;
    [_table reloadData];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)add {
    IVContainerCreateVC *vc = [IVContainerCreateVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        nav.sheetPresentationController.detents = @[ [UISheetPresentationControllerDetent mediumDetent],
                                                      [UISheetPresentationControllerDetent largeDetent] ];
        nav.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

- (UIView *)emptyStateView {
    UIView *v = [UIView new];
    v.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.stack.3d.up.fill"]];
    icon.tintColor = [UIColor tertiaryLabelColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:icon];

    UILabel *title = [UILabel new];
    title.text = @"No Containers";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Create your first isolated Instagram container";
    subtitle.font = [UIFont systemFontOfSize:15];
    subtitle.textColor = [UIColor secondaryLabelColor];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 2;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:subtitle];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [btn setTitle:@"Create Container" forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius = 12;
    [btn addTarget:self action:@selector(add) forControlEvents:UIControlEventTouchUpInside];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:btn];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:v.centerYAnchor constant:-60],
        [icon.widthAnchor constraintEqualToConstant:80],
        [icon.heightAnchor constraintEqualToConstant:80],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
        [title.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:32],
        [subtitle.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-32],
        [btn.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:24],
        [btn.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:40],
        [btn.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-40],
        [btn.heightAnchor constraintEqualToConstant:50]
    ]];
    return v;
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    IVContainer *c = _items[ip.row];
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // Clear subviews
    for (UIView *sv in cell.contentView.subviews) [sv removeFromSuperview];

    // Card background
    UIView *card = [UIView new];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 16;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.08;
    card.layer.shadowRadius = 8;
    card.layer.shadowOffset = CGSizeMake(0, 2);
    card.clipsToBounds = NO;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
        [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16]
    ]];

    // Color indicator
    UIView *colorDot = [UIView new];
    colorDot.backgroundColor = [[IVThemeManager shared] hex:c.color];
    colorDot.layer.cornerRadius = 6;
    colorDot.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:colorDot];

    // Active indicator
    UIView *activeDot = [UIView new];
    activeDot.backgroundColor = c.active ? [UIColor systemGreenColor] : [UIColor systemGray4Color];
    activeDot.layer.cornerRadius = 5;
    activeDot.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:activeDot];

    // Name
    UILabel *name = [UILabel new];
    name.text = c.name;
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    name.textColor = [UIColor labelColor];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];

    // Device info
    UILabel *device = [UILabel new];
    device.text = [NSString stringWithFormat:@"%@ · iOS %@", c.device.modelName ?: c.device.model, c.device.osVersion];
    device.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    device.textColor = [UIColor secondaryLabelColor];
    device.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:device];

    // Location
    if (c.hasLocation) {
        UILabel *loc = [UILabel new];
        loc.text = [NSString stringWithFormat:@"📍 %@", c.locName ?: @"Custom Location"];
        loc.font = [UIFont systemFontOfSize:12];
        loc.textColor = [UIColor systemBlueColor];
        loc.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:loc];

        [NSLayoutConstraint activateConstraints:@[
            [colorDot.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [colorDot.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [colorDot.widthAnchor constraintEqualToConstant:12],
            [colorDot.heightAnchor constraintEqualToConstant:12],
            [activeDot.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [activeDot.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [activeDot.widthAnchor constraintEqualToConstant:10],
            [activeDot.heightAnchor constraintEqualToConstant:10],
            [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [name.leadingAnchor constraintEqualToAnchor:colorDot.trailingAnchor constant:12],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:activeDot.leadingAnchor constant:-12],
            [device.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
            [device.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [device.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
            [loc.topAnchor constraintEqualToAnchor:device.bottomAnchor constant:4],
            [loc.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [loc.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
            [loc.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [colorDot.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [colorDot.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [colorDot.widthAnchor constraintEqualToConstant:12],
            [colorDot.heightAnchor constraintEqualToConstant:12],
            [activeDot.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [activeDot.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [activeDot.widthAnchor constraintEqualToConstant:10],
            [activeDot.heightAnchor constraintEqualToConstant:10],
            [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
            [name.leadingAnchor constraintEqualToAnchor:colorDot.trailingAnchor constant:12],
            [name.trailingAnchor constraintLessThanOrEqualToAnchor:activeDot.leadingAnchor constant:-12],
            [device.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
            [device.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
            [device.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
            [device.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
        ]];
    }

    // Tap to activate/deactivate
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cellTapped:)];
    tap.numberOfTapsRequired = 1;
    card.tag = ip.row;
    card.userInteractionEnabled = YES;
    [card addGestureRecognizer:tap];

    return cell;
}

- (void)cellTapped:(UITapGestureRecognizer *)g {
    NSInteger row = g.view.tag;
    if (row >= _items.count) return;
    IVContainer *c = _items[row];
    IVContainerManager *m = [IVContainerManager shared];
    if (c.active) {
        [m deactivate];
    } else {
        [m activate:c];
    }
    [self refresh];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style == UITableViewCellEditingStyleDelete) {
        IVContainer *c = _items[ip.row];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete Container"
                                                                   message:[NSString stringWithFormat:@"Remove \"%@\"?", c.name]
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [[IVContainerManager shared] remove:c];
        }]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end