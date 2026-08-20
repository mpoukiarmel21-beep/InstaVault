#import "IVContainerCreateVC.h"
#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVMapPickerVC.h"

@interface IVContainerCreateVC ()
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, assign) CLLocationCoordinate2D coord;
@property (nonatomic, copy) NSString *locName;
@property (nonatomic, copy) NSString *color;
@end

@implementation IVContainerCreateVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"New Container"; self.color=@"#007AFF"; self.locName=@""; self.coord=CLLocationCoordinate2DMake(0,0);
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Create" style:UIBarButtonItemStyleDone target:self action:@selector(create)];
    self.tableView.backgroundColor=UIColor.systemBackgroundColor;
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)create {
    NSString *n=self.nameField.text.length?self.nameField.text:@"Container";
    IVContainer *c=[[IVContainerManager shared] create:n];
    if(self.coord.latitude!=0||self.coord.longitude!=0){c.location=self.coord;c.locName=self.locName;}
    c.color=self.color;[[IVContainerManager shared] save];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s==0?1:2; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if(ip.section==0){
        UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"c_name"];
        if(!c)c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c_name"];
        if(!self.nameField){self.nameField=[[UITextField alloc] initWithFrame:CGRectMake(16,0,c.bounds.size.width-32,c.bounds.size.height)];self.nameField.placeholder=@"Container name";self.nameField.borderStyle=UITextBorderStyleNone;self.nameField.autocorrectionType=UITextAutocorrectionTypeNo;self.nameField.autoresizingMask=UIViewAutoresizingFlexibleWidth;[c addSubview:self.nameField];}c.textLabel.text=@"";return c;
    }
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    if(ip.row==0){c.textLabel.text=@"Location (GPS)";c.detailTextLabel.text=self.locName.length?self.locName:@"Not set";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
    else{c.textLabel.text=@"Color";c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    UIView *d=[[UIView alloc] initWithFrame:CGRectMake(c.bounds.size.width-48,8,28,28)];d.layer.cornerRadius=14;d.layer.masksToBounds=YES;d.tag=99;
    unsigned int v=0;NSScanner *sc=[NSScanner scannerWithString:self.color];[sc setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@"#"]];[sc scanHexInt:&v];
    d.backgroundColor=[UIColor colorWithRed:((v>>16)&0xFF)/255.0 green:((v>>8)&0xFF)/255.0 blue:(v&0xFF)/255.0 alpha:1];
    for(UIView *sv in c.contentView.subviews)if(sv.tag==99)[sv removeFromSuperview];[c.contentView addSubview:d];}
    return c;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return s==0?@"Name":@"Options"; }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if(ip.section==1&&ip.row==0){IVMapPickerVC *m=[IVMapPickerVC new];m.onPick=^(CLLocationCoordinate2D c,NSString *n){self.coord=c;self.locName=n;[self.tableView reloadData];};[self.navigationController pushViewController:m animated:YES];}
    else if(ip.section==1&&ip.row==1){[self pickColor];}
}
- (void)pickColor {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Color" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *cs=@[@[@"Blue",@"#007AFF"],@[@"Green",@"#34C759"],@[@"Red",@"#FF3B30"],@[@"Orange",@"#FF9500"],@[@"Purple",@"#AF52DE"],@[@"Pink",@"#FF2D55"],@[@"Teal",@"#5AC8FA"],@[@"Indigo",@"#5856D6"]];
    for(NSArray *c in cs)[a addAction:[UIAlertAction actionWithTitle:c[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *ac){self.color=c[1];[self.tableView reloadData];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end
