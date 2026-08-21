#import "IVContainerCreateVC.h"
#import "IVMapPickerVC.h"
#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVFakeDevice.h"
#import "IVThemeManager.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, IVCreateSection) {
    IVCreateSectionName,
    IVCreateSectionDevice,
    IVCreateSectionLocation,
    IVCreateSectionCount
};

@interface IVContainerCreateVC () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) IVFakeDevice *device;
@property (nonatomic, assign) CLLocationCoordinate2D coord;
@property (nonatomic, copy) NSString *locName;
@property (nonatomic, strong) UIButton *saveBtn;
@end

@implementation IVContainerCreateVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"New Container";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(cancel)];

    @try {
        _device = [IVFakeDevice generate];
    } @catch (NSException *e) {
        NSLog(@"[InstaVault] Exception generating device: %@", e);
        _device = [IVFakeDevice new];
    }

    _nameField = [[UITextField alloc] init];
    _nameField.placeholder = @"My Instagram Account";
    _nameField.borderStyle = UITextBorderStyleNone;
    _nameField.font = [UIFont systemFontOfSize:17];
    _nameField.textColor = [UIColor labelColor];
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.delegate = self;

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    _table.delegate = self;
    _table.dataSource = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:_table];

    _saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _saveBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_saveBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_saveBtn setTitle:@"Create Container" forState:UIControlStateNormal];
    _saveBtn.backgroundColor = [UIColor systemBlueColor];
    _saveBtn.layer.cornerRadius = 14;
    [_saveBtn addTarget:self action:@selector(create) forControlEvents:UIControlEventTouchUpInside];
    _saveBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_saveBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_saveBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_saveBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_saveBtn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [_saveBtn.heightAnchor constraintEqualToConstant:54]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillShow:(NSNotification *)n {
    CGRect r = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat h = r.size.height;
    _table.contentInset = UIEdgeInsetsMake(0, 0, h, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
}

- (void)keyboardWillHide:(NSNotification *)n {
    _table.contentInset = UIEdgeInsetsZero;
    _table.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)create {
    [self.view endEditing:YES];
    @try {
        NSString *n = (_nameField.text.length > 0) ? _nameField.text : @"Container";
        IVContainerManager *m = [IVContainerManager shared];
        IVContainer *c = [m create:n];
        c.device = _device;
        if (self.coord.latitude != 0 || self.coord.longitude != 0) {
            c.location = self.coord;
            c.locName = self.locName;
        }
        [m save];
        [m activate:c];
        [self dismissViewControllerAnimated:YES completion:nil];
    } @catch (NSException *e) {
        NSLog(@"[InstaVault] Exception creating container: %@", e);
    }
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return IVCreateSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case IVCreateSectionName: return 1;
        case IVCreateSectionDevice: return 2;
        case IVCreateSectionLocation: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case IVCreateSectionName: return @"Container Name";
        case IVCreateSectionDevice: return @"Device Identity";
        case IVCreateSectionLocation: return @"Fake Location";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case IVCreateSectionName: return @"A unique name to identify this container";
        case IVCreateSectionDevice: return @"Each container gets a unique device identity";
        case IVCreateSectionLocation: return @"Optional: Set a fake GPS location";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == IVCreateSectionName) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NameCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (_nameField.superview != cell.contentView) {
            [cell.contentView addSubview:_nameField];
        }
        _nameField.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [_nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            [_nameField.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [_nameField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16]
        ]];
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DetailCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    switch (ip.section) {
        case IVCreateSectionDevice: {
            if (ip.row == 0) {
                cell.textLabel.text = @"Model";
                cell.detailTextLabel.text = _device.modelName ?: _device.model ?: @"Unknown";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (ip.row == 1) {
                cell.textLabel.text = @"iOS Version";
                cell.detailTextLabel.text = _device.osVersion ?: @"Unknown";
            }
            break;
        }
        case IVCreateSectionLocation: {
            if (ip.row == 0) {
                BOOL hasLoc = (self.coord.latitude != 0 || self.coord.longitude != 0);
                cell.textLabel.text = hasLoc
                    ? [NSString stringWithFormat:@"Location: %@", self.locName ?: @"Custom"]
                    : @"Set Fake Location";
                cell.textLabel.textColor = hasLoc ? [UIColor labelColor] : [UIColor systemBlueColor];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (ip.row == 1) {
                cell.textLabel.text = @"Clear Location";
                cell.textLabel.textColor = [UIColor systemRedColor];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                BOOL hasLoc = (self.coord.latitude != 0 || self.coord.longitude != 0);
                cell.hidden = !hasLoc;
            }
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == IVCreateSectionDevice && ip.row == 0) {
        [self showModelPicker];
    } else if (ip.section == IVCreateSectionLocation) {
        if (ip.row == 0) {
            IVMapPickerVC *m = [IVMapPickerVC new];
            m.onPick = ^(CLLocationCoordinate2D c, NSString *name) {
                self.coord = c;
                self.locName = name;
                [tv reloadData];
            };
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:m];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:nil];
        } else if (ip.row == 1) {
            self.coord = CLLocationCoordinate2DMake(0, 0);
            self.locName = nil;
            [tv reloadData];
        }
    }
}

- (void)showModelPicker {
    NSArray *models = @[@"iPhone 16 Pro Max", @"iPhone 16 Pro", @"iPhone 16 Plus", @"iPhone 16",
                        @"iPhone 15 Pro Max", @"iPhone 15 Pro", @"iPhone 15 Plus", @"iPhone 15",
                        @"iPhone 14 Pro Max", @"iPhone 14 Pro", @"iPhone 14", @"iPhone 13 Pro Max"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Select Model" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *m in models) {
        [a addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
            for (IVFakeDevice *d in [IVFakeDevice allModels]) {
                if ([d.modelName isEqualToString:m]) {
                    _device = d;
                    [self.table reloadData];
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
