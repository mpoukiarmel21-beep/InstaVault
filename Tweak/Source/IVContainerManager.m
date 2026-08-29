#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVDeviceSpoofing.h"
#import "IVLocationSpoofing.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"

NSString *const kIVListChanged = @"kIVListChanged";
NSString *const kIVActiveChanged = @"kIVActiveChanged";

@implementation IVContainerManager

+ (instancetype)shared {
    static IVContainerManager *i;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [self new]; });
    return i;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _list = [NSMutableArray new];
        _active = nil;
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (NSString *)listFile {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [IVPaths controlDir];
    if (!dir.length) return nil;
    NSString *containersDir = [dir stringByAppendingPathComponent:@"Containers"];
    if (![fm fileExistsAtPath:containersDir]) {
        [fm createDirectoryAtPath:containersDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [containersDir stringByAppendingPathComponent:@"list.plist"];
}

- (void)load {
    [_lock lock];
    NSString *f = [self listFile];
    if ([[NSFileManager defaultManager] fileExistsAtPath:f]) {
        NSData *data = [NSData dataWithContentsOfFile:f];
        if (data) {
            NSArray *arr = [NSKeyedUnarchiver unarchiveObjectWithData:data];
            if (arr) {
                for (NSDictionary *d in arr) {
                    IVContainer *c = [[IVContainer alloc] initWithDict:d];
                    if (c) [_list addObject:c];
                }
                for (IVContainer *c in _list) {
                    if (c.active) { _active = c; break; }
                }
            }
        }
    }
    [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Loaded %lu containers", (unsigned long)_list.count]];
    [_lock unlock];
}

- (void)save {
    NSMutableArray *arr = [NSMutableArray new];
    for (IVContainer *c in _list) [arr addObject:c.toDict];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:arr requiringSecureCoding:NO error:nil];
    [data writeToFile:[self listFile] atomically:YES];
    [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Saved %lu containers", (unsigned long)_list.count]];
}

- (IVContainer *)create:(NSString *)name {
    IVContainer *c;
    [_lock lock];
    c = [IVContainer withName:name];
    [_list addObject:c];
    [_lock unlock];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    return c;
}

- (void)remove:(IVContainer *)c {
    [_lock lock];
    BOOL wasActive = (c == _active);
    [_list removeObject:c];
    if (wasActive) _active = _list.firstObject;
    [_lock unlock];
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
}

- (void)activate:(IVContainer *)c {
    [_lock lock];
    for (IVContainer *x in _list) x.active = (x == c);
    _active = c;
    if (c) c.lastUsed = [NSDate date];
    [_lock unlock];
    [self save];

    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Activated: %@", c.name]];

    [self relaunchForIsolation];
}

- (void)deactivate {
    [_lock lock];
    if (_active) _active.active = NO;
    _active = nil;
    [_lock unlock];
    [self save];

    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
    [[IVDiagnostics shared] info:@"Deactivated all"];

    [self relaunchForIsolation];
}

// Isolation (HOME/Keychain/CFPreferences/App-Group redirects) is applied ONCE at
// process load and cannot be re-pointed mid-process, so any change to the active
// container must be followed by a clean cold relaunch for the new isolation to
// take effect (the constructor re-applies it for the newly active container).
- (void)relaunchForIsolation {
    dispatch_async(dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end