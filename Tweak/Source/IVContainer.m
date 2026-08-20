#import "IVContainer.h"
#import "IVFakeDevice.h"

@implementation IVContainer
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)withName:(NSString *)n { IVContainer *c=[self alloc]; c.name=n; return c; }
- (instancetype)init {
    self=[super init]; if(self){
    _cid=[[NSUUID UUID] UUIDString];_name=@"Container";_device=[IVFakeDevice generate];
    _location=CLLocationCoordinate2DMake(0,0);_locName=@"";_color=@"#007AFF";
    _active=NO;_created=[NSDate date];_lastUsed=[NSDate date];
    } return self;
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self=[super init]; if(self){
    _cid=[c decodeObjectOfClass:[NSString class] forKey:@"cid"];
    _name=[c decodeObjectOfClass:[NSString class] forKey:@"name"];
    _device=[c decodeObjectOfClass:[IVFakeDevice class] forKey:@"dev"];
    _location=CLLocationCoordinate2DMake([c decodeDoubleForKey:@"lat"],[c decodeDoubleForKey:@"lon"]);
    _locName=[c decodeObjectOfClass:[NSString class] forKey:@"loc"];
    _color=[c decodeObjectOfClass:[NSString class] forKey:@"clr"];
    _active=[c decodeBoolForKey:@"act"];
    _created=[c decodeObjectOfClass:[NSDate class] forKey:@"cr"];
    _lastUsed=[c decodeObjectOfClass:[NSDate class] forKey:@"lu"];
    } return self;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_cid forKey:@"cid"];[c encodeObject:_name forKey:@"name"];
    [c encodeObject:_device forKey:@"dev"];
    [c encodeDouble:_location.latitude forKey:@"lat"];[c encodeDouble:_location.longitude forKey:@"lon"];
    [c encodeObject:_locName forKey:@"loc"];[c encodeObject:_color forKey:@"clr"];
    [c encodeBool:_active forKey:@"act"];
    [c encodeObject:_created forKey:@"cr"];[c encodeObject:_lastUsed forKey:@"lu"];
}
- (NSDictionary *)toDict {
    return @{@"cid":_cid,@"name":_name,@"dev":[_device toDict],
             @"lat":@(_location.latitude),@"lon":@(_location.longitude),
             @"loc":_locName,@"clr":_color,@"act":@(_active),
             @"cr":_created,@"lu":_lastUsed};
}
- (instancetype)initWithDict:(NSDictionary *)d {
    self=[super init]; if(self){
    _cid=d[@"cid"]?:[[NSUUID UUID] UUIDString];_name=d[@"name"]?:@"Container";
    _device=[[IVFakeDevice alloc] initWithDictionary:d[@"dev"]];
    _location=CLLocationCoordinate2DMake([d[@"lat"] doubleValue],[d[@"lon"] doubleValue]);
    _locName=d[@"loc"]?:@"";_color=d[@"clr"]?:@"#007AFF";
    _active=[d[@"act"] boolValue];_created=d[@"cr"]?:[NSDate date];_lastUsed=d[@"lu"]?:[NSDate date];
    } return self;
}
- (BOOL)hasLocation { return _location.latitude!=0||_location.longitude!=0; }
- (NSString *)sandbox {
    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    return [docs stringByAppendingPathComponent:[@"InstaVault/" stringByAppendingString:_cid]];
}
- (NSString *)cookiePath { return [[self sandbox] stringByAppendingPathComponent:@"Cookies"]; }
@end
