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

// Le conteneur actif n'est appliqué qu'UNE fois, au lancement (redirections
// HOME/keychain/prefs + spoof device/locale dans le constructeur). Basculer de
// conteneur exige donc un vrai redémarrage du process. iOS n'autorise pas une
// app à se relancer elle-même : on la met en arrière-plan (animation « home »
// pour ne pas ressembler à un crash) puis on quitte proprement ; il suffit de
// rouvrir l'app pour qu'elle démarre sur le conteneur fraîchement activé.
static void IVCloseAppForSwitch(void) {
    UIApplication *app = UIApplication.sharedApplication;
    SEL suspend = NSSelectorFromString(@"suspend");
    if ([app respondsToSelector:suspend]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [app performSelector:suspend];   // animate to home first (not a crash)
#pragma clang diagnostic pop
    }
    // Terminate so the NEXT open cold-launches on the freshly activated container.
    // The exit MUST NOT ride the main queue: once -suspend moves the app to the
    // background the main run loop stops being serviced, so a main-queue
    // dispatch_after may NEVER fire — the process is then left merely SUSPENDED
    // (resumable from the app switcher). A warm resume does not re-run the
    // constructor, so it reuses the OLD container's isolation while the store
    // already points at the newly activated one — surfacing the account on the
    // wrong (often default) identity. A background global-queue timer still runs
    // during the brief pre-suspension grace window; and even if the OS freezes it
    // first, Bootstrap's foreground stale-guard terminates the stale process on
    // the next resume, so the switch can never silently fail.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ exit(0); });
}

@interface IVPanelVC () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<IVContainer *> *items;
@end

@implementation IVPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Whamscale";   // back button / accessibilité ; titleView dessine la marque

    // Dark violet-tinted surface everywhere; force Dark so system controls
    // (alerts, text fields, the pushed map/create screens) match.
    self.view.backgroundColor = IVTheme.panelBackground;
    self.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Barre compacte (plus de grand titre) avec une marque discrète à côté du
    // wordmark, pour que la liste des conteneurs remonte et lise comme une seule
    // surface fluide.
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = NO;
    bar.tintColor = IVTheme.accent;
    self.navigationItem.titleView = [self makeBrandTitleView];

    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = IVTheme.panelBackground;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName: IVTheme.primaryText };
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
    if (@available(iOS 15.0, *)) {
        self.table.sectionHeaderTopPadding = 0.0;   // pas d'espace mort au-dessus de la 1re ligne
    }
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
    // Affordances de fin de ligne : une épingle de localisation (fake GPS) sur
    // CHAQUE conteneur, plus un glyphe iPhone (identité device) et un écrou
    // (langue/région) sur les conteneurs isolés seulement — le conteneur par défaut
    // reporte le vrai appareil. L'épingle passe en accent dès qu'une localisation
    // est posée. Le tap sur la ligne ouvre toujours Activer / Renommer / …
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = [self trailingControlsForRow:ip.row];
    return cell;
}

// The cell's accessoryView: [ 📱 ⚙︎ 📍 ] for isolated containers, [ 📍 ] for the
// default one. Each button carries the row index in its tag so the handler
// resolves the container at tap time (self.items stays in sync across reloads).
- (nullable UIView *)trailingControlsForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return nil;
    IVContainer *c = self.items[row];

    NSMutableArray<UIButton *> *btns = [NSMutableArray new];
    if (!c.isDefault) {
        [btns addObject:[self glyphButton:@"iphone" row:row
                                   action:@selector(showDeviceInfo:) tint:IVTheme.secondaryText]];
        [btns addObject:[self glyphButton:@"gearshape" row:row
                                   action:@selector(showSettings:) tint:IVTheme.secondaryText]];
    }
    // Fake GPS available on every container; accent once a location is set.
    BOOL loc = c.hasLocation;
    [btns addObject:[self glyphButton:(loc ? @"mappin.circle.fill" : @"mappin.and.ellipse")
                                  row:row action:@selector(editLocationFromControl:)
                                 tint:(loc ? IVTheme.accent : IVTheme.secondaryText)]];

    const CGFloat size = 34.0, stride = 38.0;
    CGFloat width = (btns.count - 1) * stride + size;
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, size)];
    [btns enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *stop) {
        b.frame = CGRectMake(i * stride, 0, size, size);
        [wrap addSubview:b];
    }];
    return wrap;
}

- (UIButton *)glyphButton:(NSString *)symbol row:(NSInteger)row action:(SEL)action tint:(UIColor *)tint {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    b.tintColor = tint;
    b.tag = row;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
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
    // Le choix est persisté : il reste à redémarrer pour l'appliquer. On ferme
    // l'app automatiquement après une brève confirmation (aucun bouton — la
    // fermeture est le geste). Le conteneur par défaut reste intact comme
    // repli : activer un autre conteneur ne le supprime jamais.
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Conteneur activé"
        message:[NSString stringWithFormat:@"« %@ » est prêt.\nL'app va se fermer — rouvre-la pour l'utiliser.", c.name]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    a.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ IVCloseAppForSwitch(); });
    }];
}

- (void)editLocationFromControl:(UIButton *)sender {
    IVContainer *c = [self containerForControl:sender];
    if (c) [self editLocation:c];
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
        message:@"Déconnecte AUSSI le compte principal : efface tous les cookies et sessions "
                @"Instagram du téléphone et supprime tous les conteneurs. L'app se fermera. "
                @"Irréversible."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Réinitialiser" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] resetAll]) {
            // The wipe cleared the on-disk + keychain + in-memory session, but the
            // running Instagram process still holds live session state (NSURLSession,
            // WebKit) that it would re-persist over the freshly cleared files on the
            // next flush. Cold-close so the next open relaunches truly logged out.
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *done = [UIAlertController
                    alertControllerWithTitle:@"Réinitialisé"
                                     message:@"Compte déconnecté et données effacées. "
                                             @"L'app va se fermer — rouvre-la."
                              preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"Fermer"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *y) {
                    IVCloseAppForSwitch();
                }]];
                [self presentViewController:done animated:YES completion:nil];
            });
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

// A small, restrained brand mark shown in the nav bar beside the "Whamscale"
// wordmark: a soft accent-tinted rounded badge holding a stacked-layers glyph
// (the "isolated containers" idea). Deliberately understated — present, not loud.
- (UIView *)makeBrandTitleView {
    UILabel *word = [UILabel new];
    word.text = @"Whamscale";
    word.textColor = IVTheme.primaryText;
    word.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [word sizeToFit];

    const CGFloat badgeSize = 24.0, gap = 8.0, h = 30.0;
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, badgeSize, badgeSize)];
    badge.backgroundColor = [IVTheme.accent colorWithAlphaComponent:0.20];
    badge.layer.cornerRadius = 6.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.layer.borderWidth = 1.0;
    badge.layer.borderColor = [IVTheme.accent colorWithAlphaComponent:0.55].CGColor;

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"square.stack.3d.up.fill" withConfiguration:cfg]];
    glyph.tintColor = IVTheme.accent;
    glyph.contentMode = UIViewContentModeCenter;
    glyph.frame = badge.bounds;
    [badge addSubview:glyph];

    CGFloat w = badgeSize + gap + word.bounds.size.width;
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    badge.center = CGPointMake(badgeSize / 2.0, h / 2.0);
    [wrap addSubview:badge];
    word.frame = CGRectMake(badgeSize + gap, 0, word.bounds.size.width, h);
    [wrap addSubview:word];
    return wrap;
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
