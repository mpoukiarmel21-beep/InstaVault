#import "IVContainerStore.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"

NSString *const kIVContainersChanged = @"kIVContainersChanged";
NSString *const kIVActiveChanged = @"kIVActiveChanged";

@implementation IVContainerStore {
    NSMutableArray<IVContainer *> *_list;
    NSString *_activeCID;
    NSRecursiveLock *_lock;
}

+ (instancetype)shared {
    static IVContainerStore *i;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [self new]; });
    return i;
}

- (instancetype)init {
    if ((self = [super init])) {
        _list = [NSMutableArray new];
        _activeCID = kIVDefaultCID;
        _lock = [NSRecursiveLock new];
    }
    return self;
}

#pragma mark - Load / persist

- (void)load {
    [_lock lock];
    @try {
        [_list removeAllObjects];

        NSData *data = [NSData dataWithContentsOfFile:[IVPaths containersFile]];
        NSArray *arr = nil;
        if (data) {
            arr = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        }
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in arr) {
                IVContainer *c = [[IVContainer alloc] initWithDict:d];
                if (c) [_list addObject:c];
            }
        }

        // Guarantee exactly one default container exists.
        BOOL hasDefault = NO;
        for (IVContainer *c in _list) { if (c.isDefault) { hasDefault = YES; break; } }
        if (!hasDefault) {
            [_list insertObject:[IVContainer defaultContainer] atIndex:0];
        }

        // Active pointer.
        NSData *ad = [NSData dataWithContentsOfFile:[IVPaths activeFile]];
        NSDictionary *adict = ad ? [NSPropertyListSerialization propertyListWithData:ad options:0 format:NULL error:NULL] : nil;
        NSString *cid = [adict isKindOfClass:[NSDictionary class]] ? adict[@"activeCID"] : nil;
        _activeCID = ([cid isKindOfClass:[NSString class]] && [self _containerForCIDLocked:cid]) ? [cid copy] : kIVDefaultCID;

        [self persistLocked];   // materialize default/active on first run
        IVLog(@"Loaded %lu containers, active=%@", (unsigned long)_list.count, _activeCID);
    } @finally {
        [_lock unlock];
    }
}

- (BOOL)persistLocked {
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:_list.count];
    for (IVContainer *c in _list) [arr addObject:c.toDict];

    NSError *err = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:arr
                                                             format:NSPropertyListBinaryFormat_v1_0
                                                            options:0 error:&err];
    if (!data) { IVErr(@"serialize containers failed: %@", err); return NO; }
    if (![data writeToFile:[IVPaths containersFile] options:NSDataWritingAtomic error:&err]) {
        IVErr(@"SAVE FAILED containers -> %@ : %@", [IVPaths containersFile], err);
        return NO;
    }

    NSData *ad = [NSPropertyListSerialization dataWithPropertyList:@{ @"activeCID": _activeCID ?: kIVDefaultCID }
                                                           format:NSPropertyListBinaryFormat_v1_0
                                                          options:0 error:&err];
    if (ad && ![ad writeToFile:[IVPaths activeFile] options:NSDataWritingAtomic error:&err]) {
        IVErr(@"SAVE FAILED active -> %@ : %@", [IVPaths activeFile], err);
        return NO;
    }
    return YES;
}

- (BOOL)save {
    [_lock lock];
    @try { return [self persistLocked]; }
    @finally { [_lock unlock]; }
}

#pragma mark - Accessors

- (NSArray<IVContainer *> *)containers {
    [_lock lock];
    @try { return [_list copy]; }
    @finally { [_lock unlock]; }
}

- (NSString *)activeCID {
    [_lock lock];
    @try { return [_activeCID copy]; }
    @finally { [_lock unlock]; }
}

- (IVContainer *)activeContainer {
    [_lock lock];
    @try { return [self _containerForCIDLocked:_activeCID] ?: [self _containerForCIDLocked:kIVDefaultCID]; }
    @finally { [_lock unlock]; }
}

- (IVContainer *)_containerForCIDLocked:(NSString *)cid {
    if (![cid isKindOfClass:[NSString class]]) return nil;
    for (IVContainer *c in _list) { if ([c.cid isEqualToString:cid]) return c; }
    return nil;
}

- (IVContainer *)containerForCID:(NSString *)cid {
    [_lock lock];
    @try { return [self _containerForCIDLocked:cid]; }
    @finally { [_lock unlock]; }
}

#pragma mark - Mutations

- (IVContainer *)createWithName:(NSString *)name {
    IVContainer *c = [IVContainer containerWithName:name];
    [_lock lock];
    @try {
        // Build the on-disk skeleton FIRST: a container we can't back with a
        // directory tree must never be added or persisted (would look valid in
        // the list but fail to isolate anything at launch).
        if (![IVPaths ensureSkeletonAtRoot:[IVPaths containerRootForCID:c.cid]]) {
            IVErr(@"createWithName: skeleton build failed for %@ — not creating", c.cid);
            return nil;
        }
        [_list addObject:c];
        if (![self persistLocked]) {
            [_list removeObject:c];   // roll back: keep memory == disk
            IVErr(@"createWithName: persist failed for %@ — rolled back", c.cid);
            return nil;
        }
    } @finally { [_lock unlock]; }
    [self postOnMain:kIVContainersChanged];
    IVLog(@"Created container %@ (%@)", c.name, c.cid);
    return c;
}

- (BOOL)renameContainer:(IVContainer *)c to:(NSString *)newName {
    if (c.isDefault) return NO;
    newName = [newName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (newName.length == 0) return NO;
    [_lock lock];
    @try {
        NSString *oldName = c.name;
        c.name = newName;
        if (![self persistLocked]) {
            c.name = oldName;   // roll back
            IVErr(@"renameContainer: persist failed for %@ — rolled back", c.cid);
            return NO;
        }
    } @finally { [_lock unlock]; }
    [self postOnMain:kIVContainersChanged];
    return YES;
}

- (BOOL)removeContainer:(IVContainer *)c {
    if (c.isDefault) return NO;
    [_lock lock];
    @try {
        if ([c.cid isEqualToString:_activeCID]) return NO;   // must switch away first
        [_list removeObject:c];
        [self deleteContainerDataLocked:c.cid];
        if (![self persistLocked]) {
            IVErr(@"removeContainer: persist failed for %@ (data already deleted)", c.cid);
            return NO;
        }
    } @finally { [_lock unlock]; }
    [self postOnMain:kIVContainersChanged];
    IVLog(@"Removed container %@", c.cid);
    return YES;
}

- (BOOL)setActiveCID:(NSString *)cid {
    [_lock lock];
    @try {
        IVContainer *c = [self _containerForCIDLocked:cid];
        if (!c) return NO;
        NSString *prevActive = _activeCID;
        NSDate *prevUsed = c.lastUsedAt;
        _activeCID = [cid copy];
        c.lastUsedAt = [NSDate date];
        if (![self persistLocked]) {
            _activeCID = prevActive;   // roll back both fields
            c.lastUsedAt = prevUsed;
            IVErr(@"setActiveCID: persist failed for %@ — rolled back to %@", cid, prevActive);
            return NO;
        }
    } @finally { [_lock unlock]; }
    [self postOnMain:kIVActiveChanged];
    IVLog(@"Active container set to %@ (restart required)", cid);
    return YES;
}

- (BOOL)setLocation:(NSNumber *)lat lng:(NSNumber *)lng name:(NSString *)name forContainer:(IVContainer *)c {
    [_lock lock];
    @try {
        NSNumber *pLat = c.latitude; NSNumber *pLng = c.longitude; NSString *pName = c.locationName;
        c.latitude = lat; c.longitude = lng; c.locationName = name;
        if (![self persistLocked]) {
            c.latitude = pLat; c.longitude = pLng; c.locationName = pName;   // roll back
            IVErr(@"setLocation: persist failed for %@ — rolled back", c.cid);
            return NO;
        }
    } @finally { [_lock unlock]; }
    [self postOnMain:kIVContainersChanged];
    return YES;
}

- (BOOL)resetAll {
    [_lock lock];
    @try {
        for (IVContainer *c in [_list copy]) {
            if (!c.isDefault) [self deleteContainerDataLocked:c.cid];
        }
        IVContainer *def = [self _containerForCIDLocked:kIVDefaultCID] ?: [IVContainer defaultContainer];
        [_list removeAllObjects];
        [_list addObject:def];
        _activeCID = kIVDefaultCID;
        if (![self persistLocked]) return NO;
    } @finally { [_lock unlock]; }
    [self postOnMain:kIVContainersChanged];
    [self postOnMain:kIVActiveChanged];
    IVLog(@"Global reset complete");
    return YES;
}

- (void)deleteContainerDataLocked:(NSString *)cid {
    NSString *root = [IVPaths containerRootForCID:cid];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:root]) {
        NSError *err = nil;
        if (![fm removeItemAtPath:root error:&err]) IVErr(@"delete container data failed %@: %@", cid, err);
    }
}

- (void)postOnMain:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
    });
}

@end
