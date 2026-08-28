#import "IVListPickerVC.h"
#import "IVTheme.h"

@implementation IVListOption
+ (instancetype)value:(NSString *)value title:(NSString *)title subtitle:(NSString *)subtitle {
    IVListOption *o = [IVListOption new];
    o.value = value ?: @"";
    o.title = title ?: @"";
    o.subtitle = subtitle;
    return o;
}
@end

@interface IVListPickerVC ()
@property (nonatomic, copy) NSArray<IVListOption *> *options;
@property (nonatomic, copy) NSString *selectedValue;
@property (nonatomic, copy) void (^onPick)(IVListOption *option);
@end

@implementation IVListPickerVC

- (instancetype)initWithTitle:(NSString *)title
                      options:(NSArray<IVListOption *> *)options
                selectedValue:(NSString *)selectedValue
                       onPick:(void (^)(IVListOption *))onPick {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _options = [options copy];
        _selectedValue = [selectedValue ?: @"" copy];
        _onPick = [onPick copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // self.view IS the table view here (UITableViewController): the old code set a
    // dark background then immediately cleared it, so the picker rendered as a bare
    // washed-out (white) sheet instead of the app surface. Paint the table with the
    // panel colour and pin Dark so it matches the dark menu that pushed it, whatever
    // the system appearance.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = IVTheme.panelBackground;
    self.tableView.separatorColor = IVTheme.glassStroke;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return self.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    IVListOption *o = self.options[ip.row];
    UITableViewCellStyle style = o.subtitle.length ? UITableViewCellStyleSubtitle : UITableViewCellStyleDefault;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:@"o"];
    cell.textLabel.text = o.title;
    cell.textLabel.textColor = IVTheme.primaryText;
    cell.detailTextLabel.text = o.subtitle;
    cell.detailTextLabel.textColor = IVTheme.secondaryText;
    cell.backgroundColor = IVTheme.glassFill;
    cell.tintColor = IVTheme.accent;
    cell.accessoryType = [o.value isEqualToString:self.selectedValue]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    UIView *sel = [UIView new];
    sel.backgroundColor = IVTheme.elevatedSurface;
    cell.selectedBackgroundView = sel;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    IVListOption *o = self.options[ip.row];
    if (self.onPick) self.onPick(o);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
