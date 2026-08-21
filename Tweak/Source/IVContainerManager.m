#import "IVContainerManager.h"
#import "IVContainer.h"
#import "IVDeviceSpoofing.h"
#import "IVLocationSpoofing.h"
#import "IVDiagnostics.h"

static NSString *const kIVListPath = @"InstaVault/Containers/list.plist";

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
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = [paths.firstObject stringByAppendingPathComponent:@"InstaVault"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dir stringByAppendingPathComponent:kIVListPath];
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
    [_lock lock];
    NSMutableArray *arr = [NSMutableArray new];
    for (IVContainer *c in _list) [arr addObject:c.toDict];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:arr requiringSecureCoding:NO error:nil];
    [data writeToFile:[self listFile] atomically:YES];
    [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Saved %lu containers", (unsigned long)_list.count]];
    [_lock unlock];
}

- (IVContainer *)create:(NSString *)name {
    [_lock lock];
    IVContainer *c = [IVContainer withName:name];
    [_list addObject:c];
    [self save];
    [_lock unlock];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    return c;
}

- (void)remove:(IVContainer *)c {
    [_lock lock];
    BOOL wasActive = (c == _active);
    [_list removeObject:c];
    if (wasActive) _active = _list.firstObject;
    [self save];
    [_lock unlock];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
}

- (void)activate:(IVContainer *)c {
    [_lock lock];
    for (IVContainer *x in _list) x.active = (x == c);
    _active = c;
    if (c) c.lastUsed = [NSDate date];
    [self save];
    [_lock unlock];

    [[IVDeviceSpoofing shared] enable:c.device];
    if ([c hasLocation]) [[IVLocationSpoofing shared] enable:c.location];
    else [[IVLocationSpoofing shared] disable];

    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIVListChanged object:nil];
    [[IVDiagnostics shared] info:[NSString stringWithFormat:@"Activated: %@", c.name]];
}

- (void)deactivate {
    [_lock lock];
    if (_active) _active.active = NO;
    _active = nil;
    [self save];
    [_lock unlock];

    [[IVDeviceSpoofing shared] disable];
    [[IVLocationSpoofing shared] disable];

    [[NSNotificationCenter defaultCenter] postNotificationName:kIVActiveChanged object:nil];
    [[IVDiagnostics shared] info:@"Deactivated all"];
}

@end