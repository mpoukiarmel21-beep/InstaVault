#import "IVCreateVC.h"
#import "IVListPickerVC.h"
#import "IVTheme.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Spoof/IVDeviceIdentity.h"

#pragma mark - Create / edit

@interface IVCreateVC () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong, nullable) IVContainer *editing;   // nil == create
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, copy) NSString *chosenModel;        // identifier, e.g. "iPhone17,1"
@property (nonatomic, copy) NSString *chosenIOS;          // marketing, e.g. "26.6.1"
@end

@implementation IVCreateVC

- (instancetype)initWithContainer:(IVContainer *)container {
    if ((self = [super init])) {
        _editing = container;
        // Default a brand-new container to the newest model on the REAL chip family
        // and the newest iOS version — the "realistic, newest identity" default.
        _chosenModel = container.deviceModel.length ? container.deviceModel
                                                    : [IVDeviceIdentity defaultModel].identifier;
        _chosenIOS = container.iosVersion.length ? container.iosVersion
                                                 : [IVDeviceIdentity iosVersions].firstObject;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.editing ? @"Modifier" : @"Nouveau conteneur";
    self.view.backgroundColor = IVTheme.panelBackground;
    // Pin Dark so the grouped table, its separators and system controls read as
    // one dark surface with the pickers pushed from here.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Opaque dark nav bar (same recipe as the main panel) so this screen AND the
    // model / iOS pickers pushed from it read as one dark surface — never the bare
    // white bar the default appearance would give.
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.tintColor = IVTheme.accent;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = IVTheme.panelBackground;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName: IVTheme.primaryText };
    bar.standardAppearance = ap;
    bar.scrollEdgeAppearance = ap;
    bar.compactAppearance = ap;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(save)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)save {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = @"Conteneur";
    NSString *marketing = [IVDeviceIdentity marketingNameForIdentifier:self.chosenModel];
    IVContainerStore *store = [IVContainerStore shared];

    IVContainer *target = self.editing;
    if (target) {
        if (![store renameContainer:target to:name]) { [self warnSaveFailed]; return; }
    } else {
        target = [store createWithName:name];
        if (!target) { [self warnSaveFailed]; return; }
    }
    if (![store setDeviceModel:self.chosenModel
                    iosVersion:self.chosenIOS
                 marketingName:marketing
                  forContainer:target]) {
        [self warnSaveFailed];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)warnSaveFailed {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Échec de l'enregistrement"
        message:@"Le conteneur n'a pas pu être enregistré (écriture disque échouée). Réessaie."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table (row 0: name, row 1: model, row 2: iOS version)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 1; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 3; }

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"Modèles limités à la puce réelle (%@). Chaque conteneur répond ces informations à Instagram.",
            [IVDeviceIdentity realChipFamily]];
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"n"];
        cell.backgroundColor = IVTheme.glassFill;
        if (!self.nameField) {
            self.nameField = [[UITextField alloc] initWithFrame:CGRectInset(cell.contentView.bounds, 16, 0)];
            self.nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.nameField.placeholder = @"Nom du conteneur";
            self.nameField.text = self.editing.name;
            self.nameField.textColor = IVTheme.primaryText;
            self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.nameField.delegate = self;
        }
        [cell.contentView addSubview:self.nameField];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"v"];
    cell.backgroundColor = IVTheme.glassFill;
    cell.textLabel.textColor = IVTheme.primaryText;
    cell.detailTextLabel.textColor = IVTheme.secondaryText;
    if (ip.row == 1) {
        cell.textLabel.text = @"Modèle d'appareil";
        cell.detailTextLabel.text = [IVDeviceIdentity marketingNameForIdentifier:self.chosenModel];
    } else {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:self.chosenIOS];
        cell.textLabel.text = @"Version iOS";
        cell.detailTextLabel.text = build.length
            ? [NSString stringWithFormat:@"%@ (%@)", self.chosenIOS, build]
            : self.chosenIOS;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    UIView *sel = [UIView new];
    sel.backgroundColor = IVTheme.elevatedSurface;
    cell.selectedBackgroundView = sel;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.row == 1) {
        [self pickModel];
    } else if (ip.row == 2) {
        [self pickIOS];
    }
}

- (void)pickModel {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    for (IVDeviceModel *m in [IVDeviceIdentity modelsForRealChip]) {
        [opts addObject:[IVListOption value:m.identifier title:m.marketingName subtitle:m.identifier]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Modèle d'appareil"
                                                      options:opts
                                                selectedValue:self.chosenModel
                                                       onPick:^(IVListOption *o) {
        ws.chosenModel = o.value;
        [ws.table reloadData];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (void)pickIOS {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    for (NSString *v in [IVDeviceIdentity iosVersions]) {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:v];
        [opts addObject:[IVListOption value:v title:v subtitle:build.length ? [@"build " stringByAppendingString:build] : nil]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Version iOS"
                                                      options:opts
                                                selectedValue:self.chosenIOS
                                                       onPick:^(IVListOption *o) {
        ws.chosenIOS = o.value;
        [ws.table reloadData];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end
