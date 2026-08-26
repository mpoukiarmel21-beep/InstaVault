#import "IVCreateVC.h"
#import "IVMapPickerVC.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Spoof/IVDeviceSpoof.h"

#pragma mark - Model list (pushed picker)

@interface IVModelListVC : UITableViewController
@property (nonatomic, copy) NSString *selected;
@property (nonatomic, copy) void (^onPick)(NSString *model);
@end

@implementation IVModelListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Modèle d'appareil";
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return [IVDeviceSpoof availableModels].count;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"m"];
    NSString *m = [IVDeviceSpoof availableModels][ip.row];
    c.textLabel.text = m;
    c.accessoryType = [m isEqualToString:self.selected] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    c.tintColor = UIColor.systemPurpleColor;
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSString *m = [IVDeviceSpoof availableModels][ip.row];
    if (self.onPick) self.onPick(m);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

#pragma mark - Create / edit

@interface IVCreateVC () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong, nullable) IVContainer *editing;   // nil == create
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, copy) NSString *chosenModel;
@end

@implementation IVCreateVC

- (instancetype)initWithContainer:(IVContainer *)container {
    if ((self = [super init])) {
        _editing = container;
        _chosenModel = container.deviceModel ?: (container ? [IVDeviceSpoof effectiveModelForContainer:container] : nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.editing ? @"Modifier" : @"Nouveau conteneur";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(save)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)save {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = @"Conteneur";
    IVContainerStore *store = [IVContainerStore shared];

    if (self.editing) {
        [store renameContainer:self.editing to:name];
        self.editing.deviceModel = self.chosenModel;
        if (![store save]) { [self warnSaveFailed]; return; }
    } else {
        IVContainer *c = [store createWithName:name];
        if (!c) { [self warnSaveFailed]; return; }
        c.deviceModel = self.chosenModel;
        if (![store save]) { [self warnSaveFailed]; return; }
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

#pragma mark - Table (row 0: name, row 1: model)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 1; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 2; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"n"];
        if (!self.nameField) {
            self.nameField = [[UITextField alloc] initWithFrame:CGRectInset(cell.contentView.bounds, 16, 0)];
            self.nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.nameField.placeholder = @"Nom du conteneur";
            self.nameField.text = self.editing.name;
            self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.nameField.delegate = self;
        }
        [cell.contentView addSubview:self.nameField];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"m"];
    cell.textLabel.text = @"Modèle d'appareil";
    cell.detailTextLabel.text = self.chosenModel ?: @"Auto";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.row != 1) return;
    IVModelListVC *list = [[IVModelListVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    list.selected = self.chosenModel;
    __weak typeof(self) ws = self;
    list.onPick = ^(NSString *model) {
        ws.chosenModel = model;
        [ws.table reloadData];
    };
    [self.navigationController pushViewController:list animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end
