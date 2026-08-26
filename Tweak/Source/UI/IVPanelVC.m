#import "IVPanelVC.h"
#import "IVCreateVC.h"
#import "IVMapPickerVC.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Spoof/IVDeviceSpoof.h"

@interface IVPanelVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<IVContainer *> *items;
@end

@implementation IVPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"InstaVault";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(createNew)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
    self.table.tableFooterView = [self makeResetFooter];
    [self.view addSubview:self.table];

    for (NSString *n in @[ kIVContainersChanged, kIVActiveChanged ]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
                                                   name:n object:nil];
    }
    [self reload];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reload {
    self.items = [IVContainerStore shared].containers;
    [self.table reloadData];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @"Conteneurs (chacun = un « téléphone » isolé)";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Changer de conteneur actif nécessite un redémarrage de l'app.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:@"c"];
    IVContainer *c = self.items[ip.row];
    BOOL active = [c.cid isEqualToString:[IVContainerStore shared].activeCID];

    cell.textLabel.text = c.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:active ? UIFontWeightSemibold : UIFontWeightRegular];

    NSString *model = [IVDeviceSpoof effectiveModelForContainer:c];
    NSMutableString *sub = [NSMutableString stringWithString:c.isDefault ? @"Réel (non isolé)" : model];
    if (c.hasLocation && c.locationName.length) [sub appendFormat:@" · 📍 %@", c.locationName];
    cell.detailTextLabel.text = sub;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    cell.accessoryType = active ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDetailDisclosureButton;
    cell.tintColor = UIColor.systemPurpleColor;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self presentActionsFor:self.items[ip.row]];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    [self presentActionsFor:self.items[ip.row]];
}

#pragma mark - Per-container actions

- (void)presentActionsFor:(IVContainer *)c {
    IVContainerStore *store = [IVContainerStore shared];
    BOOL active = [c.cid isEqualToString:store.activeCID];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:c.name message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    if (!active) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Activer ce conteneur" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { [self activate:c]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Localisation (GPS)" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self editLocation:c]; }]];
    if (!c.isDefault) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Renommer" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { [self rename:c]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Supprimer" style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *a) { [self delete:c]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = self.table;
    sheet.popoverPresentationController.sourceRect = self.table.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)activate:(IVContainer *)c {
    if (![[IVContainerStore shared] setActiveCID:c.cid]) {
        [self warn:@"Échec" msg:@"Impossible d'enregistrer le conteneur actif (écriture disque échouée). Réessaie."];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Redémarrage requis"
        message:@"Ferme complètement Instagram (glisse-la hors du multitâche) puis rouvre-la pour basculer sur ce conteneur."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editLocation:(IVContainer *)c {
    IVMapPickerVC *map = [[IVMapPickerVC alloc] initWithContainer:c];
    __weak typeof(self) ws = self;
    map.onCommit = ^(CLLocationCoordinate2D coord, NSString *name) { [ws reload]; };
    [self.navigationController pushViewController:map animated:YES];
}

- (void)rename:(IVContainer *)c {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Renommer" message:nil
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = c.name; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Enregistrer" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] renameContainer:c to:a.textFields.firstObject.text]) {
            [self reload];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self warn:@"Renommage impossible" msg:@"Nom vide ou écriture disque échouée."];
            });
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)delete:(IVContainer *)c {
    if ([c.cid isEqualToString:[IVContainerStore shared].activeCID]) {
        [self warn:@"Conteneur actif" msg:@"Bascule sur un autre conteneur avant de le supprimer."];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Supprimer ce conteneur ?"
        message:@"Toutes ses données (comptes, réglages) seront effacées définitivement."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Supprimer" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] removeContainer:c]) {
            [self reload];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self warn:@"Suppression impossible" msg:@"Le conteneur est actif ou l'écriture disque a échoué."];
            });
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)createNew {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:
                                   [[IVCreateVC alloc] initWithContainer:nil]];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Global reset

- (void)confirmReset {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Tout réinitialiser ?"
        message:@"Supprime TOUS les conteneurs et leurs données, sauf le principal. Irréversible."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Réinitialiser" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] resetAll]) {
            [self reload];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self warn:@"Réinitialisation incomplète" msg:@"L'écriture disque a échoué. Réessaie."];
            });
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)warn:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (UIView *)makeResetFooter {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 72)];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, 20, wrap.bounds.size.width - 40, 44);
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [b setTitle:@"Tout réinitialiser" forState:UIControlStateNormal];
    [b setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [b addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventTouchUpInside];
    [wrap addSubview:b];
    return wrap;
}

@end
