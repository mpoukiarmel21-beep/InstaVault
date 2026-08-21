#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVDiagnostics.h"

NSString *const kIVListChanged = @"kIVListChanged";
NSString *const kIVActiveChanged = @"kIVActiveChanged";

@interface IVContainerManager ()
@property (nonatomic, strong) NSMutableArray<IVContainer *> *list;
@property (nonatomic, strong) IVContainer *active;
@end

@implementation IVContainerManager
+ (instancetype)shared {
    static IVContainerManager *i=nil; static dispatch_once_t o;
    dispatch_once(&o, ^{ i=[self new]; }); return i;
}
- (instancetype)init { self=[super init]; if(self){_list=[NSMutableArray array];} return self; }

- (NSString *)path {
    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    return [docs stringByAppendingPathComponent:@"InstaVault/Data.plist"];
}

- (IVContainer *)create:(NSString *)name {
    IVContainer *c=[IVContainer withName:name?:@"Container"];
    [self.list addObject:c];
    [[NSFileManager defaultManager] createDirectoryAtPath:[c cookiePath]
                             withIntermediateDirectories:YES attributes:nil error:nil];
    [self save];
    [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Created: %@",c.name]];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    return c;
}

- (BOOL)remove:(IVContainer *)c {
    if(!c) return NO;
    [self.list removeObject:c];
    if(self.active==c) self.active=nil;
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
    return YES;
}

- (BOOL)activate:(IVContainer *)c {
    if(!c) return NO;
    if(self.active) self.active.active=NO;
    self.active=c; c.active=YES; c.lastUsed=[NSDate date];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
    return YES;
}

- (BOOL)save {
    NSMutableArray *a=[NSMutableArray array];
    for(IVContainer *c in self.list) [a addObject:[c toDict]];
    NSString *dir=[[self path] stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [a writeToFile:[self path] atomically:YES];
}

- (BOOL)load {
    NSArray *a=[NSArray arrayWithContentsOfFile:[self path]];
    if(!a) return NO;
    [self.list removeAllObjects]; self.active=nil;
    for(NSDictionary *d in a) {
        IVContainer *c=[[IVContainer alloc] initWithDict:d];
        [self.list addObject:c];
        if(c.active) self.active=c;
    }
    return YES;
}
@end
