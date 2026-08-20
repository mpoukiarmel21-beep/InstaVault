#import "IVContainerListVC.h"
#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVContainerCreateVC.h"

@interface IVContainerListVC ()
@property (nonatomic, strong) NSArray *items;
@end

@implementation IVContainerListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"InstaVault";
    self.tableView.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismiss)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:kIVListChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:kIVActiveChanged object:nil];
    [self reload];
}
- (void)reload { self.items=[IVContainerManager shared].list.copy; [self.tableView reloadData]; }
- (void)dismiss { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)add {
    IVContainerCreateVC *vc=[IVContainerCreateVC new];
    UINavigationController *n=[[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:n animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count==0?1:self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    if(self.items.count==0){c.textLabel.text=@"Tap + to create a container";c.textLabel.textColor=UIColor.secondaryLabelColor;c.selectionStyle=UITableViewCellSelectionStyleNone;c.accessoryType=UITableViewCellAccessoryNone;}
    else{IVContainer *ct=self.items[ip.row];c.textLabel.text=ct.name;c.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    NSString *d=ct.locName.length?ct.locName:@"No location";if(ct.active)d=[d stringByAppendingString:@" • Active"];
    c.detailTextLabel.text=d;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    c.accessoryType=ct.active?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryDisclosureIndicator;c.tintColor=UIColor.systemBlueColor;}
    return c;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return self.items.count?@"Containers":nil; }
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return self.items.count>0; }
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)ed forRowAtIndexPath:(NSIndexPath *)ip {
    if(ed!=UITableViewCellEditingStyleDelete)return; IVContainer *ct=self.items[ip.row];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Delete" message:[NSString stringWithFormat:@"Delete '%@'?",ct.name] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *ac){[[IVContainerManager shared] remove:ct];[self reload];}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; if(!self.items.count)return;
    IVContainer *ct=self.items[ip.row];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:ct.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if(!ct.active)[a addAction:[UIAlertAction actionWithTitle:@"Activate" style:UIAlertActionStyleDefault handler:^(UIAlertAction *ac){[[IVContainerManager shared] activate:ct];[self reload];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *ac){[[IVContainerManager shared] remove:ct];[self reload];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
