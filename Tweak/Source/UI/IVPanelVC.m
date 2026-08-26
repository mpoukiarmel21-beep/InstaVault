#import "IVPanelVC.h"
#import "IVCreateVC.h"
#import "IVMapPickerVC.h"
#import "IVListPickerVC.h"
#import "IVTheme.h"
#import "IVActionSheet.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Spoof/IVDeviceSpoof.h"
#import "../Spoof/IVDeviceIdentity.h"
#import "../Spoof/IVLocaleSpoof.h"

@interface IVPanelVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<IVContainer *> *items;
@end

@implementation IVPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Whamscale";

    // Dark violet-tinted surface everywhere; force Dark so system controls
    // (alerts, text fields, the pushed map/create screens) match.
    self.view.backgroundColor = IVTheme.panelBackground;
    self.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Large-title nav painted with the same dark surface + violet accent.
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    bar.tintColor = IVTheme.accent;

    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = IVTheme.panelBackground;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName: IVTheme.primaryText };
    ap.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: IVTheme.primaryText };
    bar.standardAppearance = ap;
    bar.scrollEdgeAppearance = ap;
    bar.compactAppearance = ap;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(createNew)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;   // let panelBackground show through
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
    self.table.tableFooterView = [self makeResetFooter];
    // If the app launched degraded (isolation could not be applied and we fell
    // back to the REAL account), warn loudly at the top so the user does not log
    // in thinking they are inside a container.
    if ([IVContainerStore shared].isolationDegraded) {
        self.table.tableHeaderView = [self makeDegradedBanner];
    }
    [self.view addSubview:self.table];

    for (NSString *n in @[ kIVContainersChanged, kIVActiveChanged ]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
                                                   name:n object:nil];
    }
    [self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Fire onClose only on a real dismissal (Close / swipe-down), never when a
    // child (map picker) is pushed on top — so the floating button reappears at
    // the right moment.
    if ((self.isBeingDismissed || self.navigationController.isBeingDismissed) && self.onClose) {
        self.onClose();
        self.onClose = nil;
    }
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
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    IVContainer *c = self.items[ip.row];
    BOOL active = [c.cid isEqualToString:[IVContainerStore shared].activeCID];

    NSString *model = [IVDeviceSpoof effectiveModelForContainer:c];
    NSMutableString *sub = [NSMutableString stringWithString:c.isDefault ? @"Réel (non isolé)" : model];
    if (c.hasLocation && c.locationName.length) [sub appendFormat:@"  ·  📍 %@", c.locationName];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = c.name;
    content.textProperties.color = IVTheme.primaryText;
    content.textProperties.font = [UIFont systemFontOfSize:17
                                                    weight:active ? UIFontWeightSemibold : UIFontWeightRegular];
    content.secondaryText = sub;
    content.secondaryTextProperties.color = IVTheme.secondaryText;
    content.secondaryTextProperties.font = [UIFont systemFontOfSize:13];
    // Leading indicator doubles as the "active" marker (filled accent) vs idle.
    content.image = [UIImage systemImageNamed:active ? @"checkmark.circle.fill" : @"circle"];
    content.imageProperties.tintColor = active ? IVTheme.accent : IVTheme.secondaryText;
    content.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    content.imageToTextPadding = 12.0;
    cell.contentConfiguration = content;

    // Translucent-but-visible glass row over the dark surface.
    cell.backgroundColor = IVTheme.glassFill;
    UIView *sel = [UIView new];
    sel.backgroundColor = IVTheme.elevatedSurface;
    cell.selectedBackgroundView = sel;

    cell.tintColor = IVTheme.accent;
    // Trailing affordances: a phone glyph (device identity) + a gear glyph
    // (language/region). Only for isolated (non-default) containers — the default
    // container reports the real device, so there is nothing to inspect or spoof.
    // Row tap still opens the full action sheet (Activer / GPS / …).
    if (c.isDefault) {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self trailingControlsForRow:ip.row];
    }
    return cell;
}

// A compact [ 📱 ⚙︎ ] pair used as the cell's accessoryView. Buttons carry the
// row index in their tag so the handler resolves the container at tap time
// (self.items stays in sync with the table across reloads).
- (UIView *)trailingControlsForRow:(NSInteger)row {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];

    UIButton *phone = [UIButton buttonWithType:UIButtonTypeSystem];
    [phone setImage:[UIImage systemImageNamed:@"iphone" withConfiguration:cfg] forState:UIControlStateNormal];
    phone.tintColor = IVTheme.secondaryText;
    phone.tag = row;
    phone.frame = CGRectMake(0, 0, 34, 34);
    [phone addTarget:self action:@selector(showDeviceInfo:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    [gear setImage:[UIImage systemImageNamed:@"gearshape" withConfiguration:cfg] forState:UIControlStateNormal];
    gear.tintColor = IVTheme.secondaryText;
    gear.tag = row;
    gear.frame = CGRectMake(38, 0, 34, 34);
    [gear addTarget:self action:@selector(showSettings:) forControlEvents:UIControlEventTouchUpInside];

    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 34)];
    [wrap addSubview:phone];
    [wrap addSubview:gear];
    return wrap;
}

- (nullable IVContainer *)containerForControl:(UIControl *)sender {
    NSInteger row = sender.tag;
    return (row >= 0 && row < (NSInteger)self.items.count) ? self.items[row] : nil;
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
    __weak typeof(self) ws = self;

    IVActionSheet *sheet = [[IVActionSheet alloc] initWithTitle:c.name
                                                        message:active ? @"Conteneur actif" : nil];

    if (!active) {
        [sheet addAction:[IVAction actionWithTitle:@"Activer ce conteneur"
                                            symbol:@"power.circle.fill"
                                             style:IVActionStyleAccentSoft
                                           handler:^{ [ws activate:c]; }]];
    }
    [sheet addAction:[IVAction actionWithTitle:@"Localisation (GPS)"
                                        symbol:@"mappin.and.ellipse"
                                         style:IVActionStyleDefault
                                       handler:^{ [ws editLocation:c]; }]];
    if (!c.isDefault) {
        [sheet addAction:[IVAction actionWithTitle:@"Renommer"
                                            symbol:@"pencil"
                                             style:IVActionStyleDefault
                                           handler:^{ [ws rename:c]; }]];
        [sheet addAction:[IVAction actionWithTitle:@"Supprimer"
                                            symbol:@"trash"
                                             style:IVActionStyleDestructive
                                           handler:^{ [ws delete:c]; }]];
    }
    [sheet presentFrom:self];
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

#pragma mark - Device info (read-only) + settings (language / region)

- (void)showDeviceInfo:(UIButton *)sender {
    IVContainer *c = [self containerForControl:sender];
    if (!c) return;
    NSString *ident = [IVDeviceSpoof effectiveModelForContainer:c];
    NSString *marketing = [IVDeviceIdentity marketingNameForIdentifier:ident];

    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if (c.iosVersion.length) {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:c.iosVersion];
        [lines addObject:[NSString stringWithFormat:@"iOS %@%@", c.iosVersion,
                          build.length ? [NSString stringWithFormat:@" (build %@)", build] : @""]];
    } else {
        [lines addObject:@"iOS : version réelle (non forcée)"];
    }
    [lines addObject:[NSString stringWithFormat:@"Identifiant : %@", ident]];
    [lines addObject:[NSString stringWithFormat:@"N° de modèle : %@",
                      [IVDeviceIdentity modelNumberForCID:c.cid region:c.regionCountry]]];
    [lines addObject:[NSString stringWithFormat:@"N° de série : %@", [IVDeviceIdentity serialForCID:c.cid]]];
    [lines addObject:@""];
    [lines addObject:@"Ces informations sont celles répondues à Instagram (série et n° de modèle sont indicatifs, affichage seul)."];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:marketing
                                                              message:[lines componentsJoinedByString:@"\n"]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    a.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [a addAction:[UIAlertAction actionWithTitle:@"Fermer" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showSettings:(UIButton *)sender {
    IVContainer *c = [self containerForControl:sender];
    if (!c) return;
    __weak typeof(self) ws = self;

    NSString *langNow = c.appLanguage.length
        ? [IVLocaleSpoof displayNameForLanguage:c.appLanguage] : @"Automatique";
    NSString *regionNow = c.regionCountry.length
        ? [IVLocaleSpoof displayNameForRegion:c.regionCountry] : @"Automatique";

    IVActionSheet *sheet = [[IVActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"Réglages — %@", c.name]
                                                        message:@"Prend effet au prochain démarrage de l'app."];
    [sheet addAction:[IVAction actionWithTitle:[NSString stringWithFormat:@"Langue : %@", langNow]
                                        symbol:@"globe"
                                         style:IVActionStyleDefault
                                       handler:^{ [ws pickLanguageFor:c]; }]];
    [sheet addAction:[IVAction actionWithTitle:[NSString stringWithFormat:@"Région : %@", regionNow]
                                        symbol:@"map"
                                         style:IVActionStyleDefault
                                       handler:^{ [ws pickRegionFor:c]; }]];
    [sheet presentFrom:self];
}

- (void)pickLanguageFor:(IVContainer *)c {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    [opts addObject:[IVListOption value:@"" title:@"Automatique (système)" subtitle:nil]];
    for (NSString *code in [IVLocaleSpoof supportedLanguageCodes]) {
        [opts addObject:[IVListOption value:code title:[IVLocaleSpoof displayNameForLanguage:code] subtitle:code]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Langue de l'application"
                                                      options:opts
                                                selectedValue:c.appLanguage
                                                       onPick:^(IVListOption *o) {
        NSString *lang = o.value.length ? o.value : nil;
        if (![[IVContainerStore shared] setAppLanguage:lang region:c.regionCountry forContainer:c]) {
            [ws warn:@"Échec" msg:@"Impossible d'enregistrer la langue (écriture disque échouée)."];
        }
        [ws reload];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (void)pickRegionFor:(IVContainer *)c {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    [opts addObject:[IVListOption value:@"" title:@"Automatique (système)" subtitle:nil]];
    for (NSString *code in [IVLocaleSpoof supportedRegionCodes]) {
        [opts addObject:[IVListOption value:code title:[IVLocaleSpoof displayNameForRegion:code] subtitle:code]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Pays / région"
                                                      options:opts
                                                selectedValue:c.regionCountry
                                                       onPick:^(IVListOption *o) {
        NSString *region = o.value.length ? o.value : nil;
        if (![[IVContainerStore shared] setAppLanguage:c.appLanguage region:region forContainer:c]) {
            [ws warn:@"Échec" msg:@"Impossible d'enregistrer la région (écriture disque échouée)."];
        }
        [ws reload];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (void)createNew {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:
                                   [[IVCreateVC alloc] initWithContainer:nil]];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;   // match the dark menu
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

- (UIView *)makeDegradedBanner {
    CGFloat w = self.view.bounds.size.width;
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 96)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, 12, w - 40, 72)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.18];
    card.layer.cornerRadius = 14.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.55].CGColor;

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(card.bounds, 14, 10)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    l.numberOfLines = 0;
    l.textColor = IVTheme.primaryText;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.text = @"⚠️ Isolation inactive — vous êtes sur le compte réel. Ne vous connectez pas ici ; fermez complètement l'app puis rouvrez-la.";
    [card addSubview:l];
    [wrap addSubview:card];
    return wrap;
}

- (UIView *)makeResetFooter {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 88)];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, 24, wrap.bounds.size.width - 40, 52);
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [b setTitle:@"Tout réinitialiser" forState:UIControlStateNormal];
    [b setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    // Translucent glass pill so it reads as a deliberate, framed destructive action.
    b.backgroundColor = IVTheme.glassFill;
    b.layer.cornerRadius = 16.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = IVTheme.glassStroke.CGColor;
    [b addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventTouchUpInside];
    [wrap addSubview:b];
    return wrap;
}

@end
