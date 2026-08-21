#import "IVContainerCreateVC.h"
#import "IVMapPickerVC.h"
#import "IVContainerManager.h"
#import "IVFakeDevice.h"
#import "IVThemeManager.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IVCreateSection) {
    IVCreateSectionName,
    IVCreateSectionDevice,
    IVCreateSectionLocation,
    IVCreateSectionAdvanced,
    IVCreateSectionCount
};

@interface IVContainerCreateVC () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) IVFakeDevice *device;
@property (nonatomic, assign) CLLocationCoordinate2D coord;
@property (nonatomic, copy) NSString *locName;
@property (nonatomic, copy) NSString *color;
@property (nonatomic, strong) UIButton *saveBtn;
@end

@implementation IVContainerCreateVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"New Container";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    // Navigation items
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(cancel)];
    
    // Generate new device
    _device = [IVFakeDevice generate];
    _color = [IVContainer randomColor];

    // Table
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _table.registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_table];

    // Save button at bottom
    _saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _saveBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_saveBtn setTitle:@"Create Container" forState:UIControlStateNormal];
    _saveBtn.backgroundColor = [IVThemeManager shared].hex(_color);
    _saveBtn.layer.cornerRadius = 14;
    [_saveBtn addTarget:self action:@selector(create) forControlEvents:UIControlEventTouchUpInside];
    _saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_saveBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_saveBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_saveBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_saveBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [_saveBtn.heightAnchor constraintEqualToConstant:54]
    ]];

    // Adjust table inset for button
    _table.contentInset = UIEdgeInsetsMake(0, 0, 80, 0);
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)create {
    [self.view endEditing:YES];
    NSString *n = self.nameField.text.length ? self.nameField.text : @"Container";
    IVContainerManager *m = [IVContainerManager shared];
    IVContainer *c = [m create:n];
    c.device = _device;
    c.color = _color;
    if (self.coord.latitude != 0 || self.coord.longitude != 0) {
        c.location = self.coord;
        c.locName = self.locName;
    }
    [m save];
    [m activate:c];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return IVCreateSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case IVCreateSectionName: return 1;
        case IVCreateSectionDevice: return 3;
        case IVCreateSectionLocation: return 2;
        case IVCreateSectionAdvanced: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case IVCreateSectionName: return @"Container Name";
        case IVCreateSectionDevice: return @"Device Identity";
        case IVCreateSectionLocation: return @"Fake Location";
        case IVCreateSectionAdvanced: return @"Advanced";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case IVCreateSectionName: return @"A unique name to identify this container";
        case IVCreateSectionDevice: return @"Each container gets a unique iPhone model, iOS version, UDID, and identifiers";
        case IVCreateSectionLocation: return @"Optional: Set a fake GPS location for this container";
        case IVCreateSectionAdvanced: return @"Regenerate device identity or change accent color";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:ip];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *sv in cell.contentView.subviews) [sv removeFromSuperview];

    switch (ip.section) {
        case IVCreateSectionName: {
            if (ip.row == 0) {
                cell.textLabel.text = @"";
                _nameField = [[UITextField alloc] initWithFrame:CGRectZero];
                _nameField.placeholder = @"My Instagram Account";
                _nameField.borderStyle = UITextBorderStyleNone;
                _nameField.font = [UIFont systemFontOfSize:17];
                _nameField.textColor = [UIColor labelColor];
                _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
                _nameField.returnKeyType = UIReturnKeyDone;
                _nameField.delegate = self;
                _nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                _nameField.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:_nameField];
                [NSLayoutConstraint activateConstraints:@[
                    [_nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
                    [_nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
                    [_nameField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                    [_nameField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16]
                ]];
            }
            break;
        }
        case IVCreateSectionDevice: {
            if (ip.row == 0) {
                cell.textLabel.text = @"Model";
                cell.detailTextLabel.text = _device.modelName;
                cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (ip.row == 1) {
                cell.textLabel.text = @"iOS Version";
                cell.detailTextLabel.text = _device.osVersion;
                cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            } else if (ip.row == 2) {
                cell.textLabel.text = @"Regenerate Identity";
                cell.textLabel.textColor = [UIColor systemBlueColor];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            break;
        }
        case IVCreateSectionLocation: {
            if (ip.row == 0) {
                cell.textLabel.text = self.coord.latitude != 0 || self.coord.longitude != 0
                    ? [NSString stringWithFormat:@"📍 %@", self.locName ?: @"Custom Location"]
                    : @"Set Fake Location";
                cell.textLabel.textColor = self.coord.latitude != 0 ? [UIColor labelColor] : [UIColor systemBlueColor];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (ip.row == 1) {
                cell.textLabel.text = @"Clear Location";
                cell.textLabel.textColor = [UIColor systemRedColor];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                cell.hidden = !(self.coord.latitude != 0 || self.coord.longitude != 0);
            }
            break;
        }
        case IVCreateSectionAdvanced: {
            if (ip.row == 0) {
                cell.textLabel.text = @"Accent Color";
                cell.detailTextLabel.text = @"";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                
                // Color picker buttons
                NSArray *colors = @[@"#FF3B30",@"#FF9500",@"#FFCC00",@"#34C759",
                                    @"#007AFF",@"#5856D6",@"#AF52DE",@"#FF2D55"];
                UIStackView *stack = [[UIStackView alloc] init];
                stack.axis = UILayoutConstraintAxisHorizontal;
                stack.distribution = UIStackViewDistributionFillEqually;
                stack.spacing = 8;
                stack.translatesAutoresizingMaskIntoConstraints = NO;
                for (NSString *hex in colors) {
                    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
                    b.backgroundColor = [IVThemeManager shared].hex(hex);
                    b.layer.cornerRadius = 16;
                    b.layer.borderWidth = [hex isEqualToString:_color] ? 3 : 0;
                    b.layer.borderColor = [UIColor labelColor].CGColor;
                    b.tag = [colors indexOfObject:hex];
                    [b addTarget:self action:@selector(colorPicked:) forControlEvents:UIControlEventTouchUpInside];
                    [stack addArrangedSubview:b];
                    [NSLayoutConstraint activateConstraints:@[
                        [b.heightAnchor constraintEqualToConstant:32],
                        [b.widthAnchor constraintEqualToConstant:32]
                    ]];
                }
                [cell.contentView addSubview:stack];
                [NSLayoutConstraint activateConstraints:@[
                    [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                    [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                    [stack.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                    [stack.heightAnchor constraintEqualToConstant:32]
                ]];
            } else if (ip.row == 1) {
                cell.textLabel.text = @"Regenerate All Identifiers";
                cell.textLabel.textColor = [UIColor systemOrangeColor];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            }
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == IVCreateSectionDevice) {
        if (ip.row == 0) {
            // Model picker - show as action sheet
            [self showModelPicker];
        } else if (ip.row == 2) {
            _device = [IVFakeDevice generate];
            [tv reloadSections:[NSIndexSet indexSetWithIndex:IVCreateSectionDevice]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
            _saveBtn.backgroundColor = [IVThemeManager shared].hex(_color);
        }
    } else if (ip.section == IVCreateSectionLocation) {
        if (ip.row == 0) {
            IVMapPickerVC *m = [IVMapPickerVC new];
            m.onPick = ^(CLLocationCoordinate2D c, NSString *name) {
                self.coord = c;
                self.locName = name;
                [tv reloadSections:[NSIndexSet indexSetWithIndex:IVCreateSectionLocation]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:m];
            [self presentViewController:nav animated:YES completion:nil];
        } else if (ip.row == 1) {
            self.coord = CLLocationCoordinate2DMake(0, 0);
            self.locName = nil;
            [tv reloadSections:[NSIndexSet indexSetWithIndex:IVCreateSectionLocation]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    } else if (ip.section == IVCreateSectionAdvanced) {
        if (ip.row == 1) {
            _device = [IVFakeDevice generate];
            [tv reloadSections:[NSIndexSet indexSetWithIndex:IVCreateSectionDevice]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (void)colorPicked:(UIButton *)b {
    NSArray *colors = @[@"#FF3B30",@"#FF9500",@"#FFCC00",@"#34C759",
                        @"#007AFF",@"#5856D6",@"#AF52DE",@"#FF2D55"];
    _color = colors[b.tag];
    _saveBtn.backgroundColor = [IVThemeManager shared].hex(_color);
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:IVCreateSectionAdvanced]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)showModelPicker {
    NSArray *models = @[@"iPhone 16 Pro Max", @"iPhone 16 Pro", @"iPhone 16 Plus", @"iPhone 16",
                        @"iPhone 15 Pro Max", @"iPhone 15 Pro", @"iPhone 15 Plus", @"iPhone 15",
                        @"iPhone 14 Pro Max", @"iPhone 14 Pro", @"iPhone 14", @"iPhone 13 Pro Max"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Select Model" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *m in models) {
        [a addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            // Update device with selected model
            for (IVFakeDevice *d in [IVFakeDevice allModels]) {
                if ([d.modelName isEqualToString:m]) {
                    _device = d;
                    [self.table reloadSections:[NSIndexSet indexSetWithIndex:IVCreateSectionDevice]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                    break;
                }
            }
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

@end