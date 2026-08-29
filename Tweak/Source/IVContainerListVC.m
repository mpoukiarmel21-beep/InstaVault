#import "IVContainerListVC.h"
#import "IVContainerCreateVC.h"
#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVFakeDevice.h"
#import "IVFloatingButton.h"
#import "IVThemeManager.h"
#import "IVPaths.h"
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>

@interface IVContainerListVC () <UITableViewDelegate, UITableViewDataSource, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) UIBarButtonItem *cameraBarButton;
@end

@implementation IVContainerListVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"InstaVault Containers";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationController.navigationBar.prefersLargeTitles = YES;

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                       target:self action:@selector(add)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"video"]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(manageGlobalCamera)]
    ];
    _cameraBarButton = self.navigationItem.rightBarButtonItems[1];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(dismissSelf)];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    [self.view addSubview:_table];

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

- (void)refreshCameraButton {
    BOOL has = [IVPaths hasGlobalCameraVideo];
    _cameraBarButton.image = [UIImage systemImageNamed:(has ? @"video.fill" : @"video")];
    _cameraBarButton.tintColor = has ? [UIColor systemGreenColor] : nil;
}

- (void)manageGlobalCamera {
    if (![IVPaths hasGlobalCameraVideo]) { [self pickGlobalCameraVideo]; return; }
    __weak typeof(self) ws = self;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Camera virtuelle"
                                                               message:@"Vidéo de vérification définie ✓ (partagée par tous les conteneurs)"
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Changer la vidéo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [ws pickGlobalCameraVideo];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Retirer la vidéo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [IVPaths removeGlobalCameraVideo];
        [ws refreshCameraButton];
        [ws showCameraMessage:@"Caméra virtuelle désactivée" msg:@"Instagram utilisera de nouveau la vraie caméra."];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickGlobalCameraVideo {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.filter = [PHPickerFilter videosFilter];
        cfg.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        [self showCameraMessage:@"Indisponible" msg:@"La sélection de vidéo nécessite iOS 14 ou plus récent."];
    }
}

- (void)showCameraMessage:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [self showCameraMessage:@"Format non pris en charge" msg:@"Choisis une vidéo (.mov ou .mp4)."];
        return;
    }
    __weak typeof(self) ws = self;
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie"
                                    completionHandler:^(NSURL *url, NSError *error) {
        BOOL imported = (url != nil) && [IVPaths importGlobalCameraVideoFromURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!imported) {
                [ws showCameraMessage:@"Import échoué" msg:@"La vidéo n'a pas pu être copiée. Réessaie."];
                return;
            }
            [ws refreshCameraButton];
            [ws showCameraMessage:@"Vidéo enregistrée"
                              msg:@"Elle alimentera la caméra native d'Instagram lors de la vérification, sur tous les conteneurs. Redémarre l'app pour l'activer."];
        });
    }];
}

- (void)add {
    @try {
        IVContainerCreateVC *vc = [IVContainerCreateVC new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    } @catch (NSException *e) {
        NSLog(@"[InstaVault] Exception presenting create VC: %@", e);
    }
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
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    cell.textLabel.text = c.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    cell.textLabel.textColor = [UIColor labelColor];

    NSString *devStr = [NSString stringWithFormat:@"%@ · iOS %@", c.device.modelName ?: c.device.model ?: @"?", c.device.osVersion ?: @"?"];
    cell.detailTextLabel.text = devStr;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 1;

    UIView *colorDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 12)];
    colorDot.backgroundColor = c.color ? [[IVThemeManager shared] hex:c.color] : [UIColor systemBlueColor];
    colorDot.layer.cornerRadius = 6;
    cell.accessoryView = colorDot;

    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    IVContainer *c = _items[ip.row];
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
