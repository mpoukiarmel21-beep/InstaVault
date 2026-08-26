#import "IVKeychainHook.h"
#import "IVDiagnostics.h"
#import "vendor/fishhook/fishhook.h"
#import <Security/Security.h>

// The active container's keychain namespace prefix, e.g. "IV:<cid>:".
// nil == default container == hooks not installed (real keychain passthrough).
static NSString *gPrefix = nil;

// Saved originals (filled by fishhook).
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;

#pragma mark - Prefix helpers

static NSString *IVPrefixed(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return gPrefix;     // no value -> bare namespace
    if ([value hasPrefix:gPrefix]) return value;                     // already prefixed
    return [gPrefix stringByAppendingString:value];
}

static NSString *IVStripped(NSString *value) {
    if ([value isKindOfClass:[NSString class]] && [value hasPrefix:gPrefix]) {
        return [value substringFromIndex:gPrefix.length];
    }
    return value;
}

// The keychain primary-key attribute we namespace for a query's class:
//   • generic-password  -> kSecAttrService  (the service is a primary key here)
//   • internet-password -> kSecAttrServer   (the host/server is the primary key)
// Any other class (keys, certificates, identities) returns NULL and passes
// through untouched: kSecAttrService/kSecAttrServer are NOT primary keys there,
// so injecting one matches nothing on read and is rejected on write — it would
// only corrupt a legitimate query without ever isolating anything.
//
// Namespacing BOTH password classes (not just generic-password, as the first
// cut did) is what stops one container's login from clobbering another's: an
// app that keeps any session material in an internet-password item used to
// SHARE that item across every container (last writer wins), so logging into a
// 2nd account and returning to the 1st found the 2nd's shared item and forced a
// re-login. Isolating kSecAttrServer too closes that leak; it is a strict
// superset — a no-op for apps that use no internet-password items.
static CFStringRef IVNamespaceField(NSDictionary *m) {
    id cls = m[(__bridge id)kSecClass];
    if (cls == nil) return NULL;
    if ([cls isEqual:(__bridge id)kSecClassGenericPassword])  return kSecAttrService;
    if ([cls isEqual:(__bridge id)kSecClassInternetPassword]) return kSecAttrServer;
    return NULL;
}

// A query that identifies its item by an explicit reference — a persistent ref
// (kSecValuePersistentRef) or an explicit item list (kSecMatchItemList) — already
// targets one exact item. That reference could only have been handed back by a
// prior query that WAS namespaced, so it is container-safe as-is. Forcing a
// field constraint onto such a query is actively harmful: the stored item's
// field is the *namespaced* string, not the bare prefix we would inject, so the
// added constraint filters the referenced item straight out and the lookup
// fails. Detect these and pass the query through untouched.
static BOOL IVQueryHasExplicitRef(NSDictionary *m) {
    return m[(__bridge id)kSecValuePersistentRef] != nil ||
           m[(__bridge id)kSecMatchItemList] != nil;
}

// Returns a retained copy of `query` with its namespace field prefixed.
// When `injectWhenAbsent` is YES and the field is missing, a bare prefix is set
// — used by Add/Update/Delete so a field-less item is still isolated per
// container. Reads never call this with a missing field (field-less enumeration
// is handled specially in iv_SecItemCopyMatching). Non-namespaced (see
// IVNamespaceField) or ref-keyed queries are returned unchanged.
static CFDictionaryRef IVCopyNamespacedQuery(CFDictionaryRef query, BOOL injectWhenAbsent) {
    NSMutableDictionary *m = query ? [(__bridge NSDictionary *)query mutableCopy] : [NSMutableDictionary new];
    CFStringRef field = IVNamespaceField(m);
    if (field == NULL || IVQueryHasExplicitRef(m)) {
        return (__bridge_retained CFDictionaryRef)m;   // not namespaced OR ref-keyed: untouched
    }
    id val = m[(__bridge id)field];
    if ([val isKindOfClass:[NSString class]]) {
        m[(__bridge id)field] = IVPrefixed(val);
    } else if (injectWhenAbsent) {
        m[(__bridge id)field] = gPrefix;
    }
    return (__bridge_retained CFDictionaryRef)m;
}

// Strip our prefix from BOTH namespaceable fields of a returned attribute dict
// (only one is ever present per item), rewriting them to the app-visible value.
static void IVStripFieldsInPlace(NSMutableDictionary *m) {
    id svc = m[(__bridge id)kSecAttrService];
    if ([svc isKindOfClass:[NSString class]]) m[(__bridge id)kSecAttrService] = IVStripped(svc);
    id srv = m[(__bridge id)kSecAttrServer];
    if ([srv isKindOfClass:[NSString class]]) m[(__bridge id)kSecAttrServer] = IVStripped(srv);
}

// Rewrites the namespaced field(s) in a returned attribute dictionary back to
// the app-visible value. Returns the (possibly rewritten) object.
static id IVStripResultObject(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [obj mutableCopy];
        IVStripFieldsInPlace(d);
        return d;
    }
    return obj;
}

// Reshape one discovered attribute dict back into the exact return shape the
// caller's ORIGINAL query asked for. We force kSecReturnAttributes on the
// discovery query (so every result carries its namespace field for filtering);
// this undoes that, handing back raw data / a persistent-ref / a value dict /
// the attribute dict as appropriate, with our prefix stripped. Returns nil when
// the caller requested no return payload at all.
static id IVReshapeItem(NSDictionary *d, BOOL wantData, BOOL wantAttrs,
                        BOOL wantPRef, BOOL wantRef) {
    NSMutableDictionary *m = [d mutableCopy];
    IVStripFieldsInPlace(m);

    if (wantAttrs) {
        // Caller wanted attributes: Security already merged any requested value
        // keys (data / persistent-ref) into this dict. Hand it back stripped.
        return m;
    }
    int n = (wantData ? 1 : 0) + (wantPRef ? 1 : 0) + (wantRef ? 1 : 0);
    if (n <= 1) {
        if (wantData) return m[(__bridge id)kSecValueData];
        if (wantPRef) return m[(__bridge id)kSecValuePersistentRef];
        if (wantRef)  return m[(__bridge id)kSecValueRef];
        return nil;   // caller requested no return payload
    }
    // Multiple raw values, no attributes: dict of just the requested value keys.
    NSMutableDictionary *vals = [NSMutableDictionary dictionary];
    id data = m[(__bridge id)kSecValueData];
    id pref = m[(__bridge id)kSecValuePersistentRef];
    id ref  = m[(__bridge id)kSecValueRef];
    if (wantData && data) vals[(__bridge id)kSecValueData] = data;
    if (wantPRef && pref) vals[(__bridge id)kSecValuePersistentRef] = pref;
    if (wantRef  && ref)  vals[(__bridge id)kSecValueRef] = ref;
    return vals;
}

#pragma mark - Diagnostics (keychain-usage map)

static NSString *IVClassName(id cls) {
    if ([cls isEqual:(__bridge id)kSecClassGenericPassword])  return @"genp";
    if ([cls isEqual:(__bridge id)kSecClassInternetPassword]) return @"inet";
    if ([cls isEqual:(__bridge id)kSecClassKey])              return @"key";
    if ([cls isEqual:(__bridge id)kSecClassCertificate])      return @"cert";
    if ([cls isEqual:(__bridge id)kSecClassIdentity])         return @"idnt";
    return cls ? @"other" : @"none";
}

// Log each DISTINCT keychain-op signature ONCE, so a device test reveals exactly
// which item classes and key attributes Instagram touches during login WITHOUT
// spamming the ring log or ever recording a secret value. This is how we finally
// answer, with real data, whether session material lives in a class we do not yet
// namespace (kSecClassKey / identity) — the open question behind any residual
// "spinning on login". Only the PRESENCE of attributes is read, never a value.
static void IVLogKeychainOp(NSString *op, NSDictionary *m) {
    if (!m) return;
    NSString *cls = IVClassName(m[(__bridge id)kSecClass]);
    NSMutableArray *f = [NSMutableArray array];
    if (m[(__bridge id)kSecAttrService])          [f addObject:@"svc"];
    if (m[(__bridge id)kSecAttrServer])           [f addObject:@"srv"];
    if (m[(__bridge id)kSecAttrAccount])          [f addObject:@"acct"];
    if (m[(__bridge id)kSecAttrApplicationTag])   [f addObject:@"tag"];
    if (m[(__bridge id)kSecAttrApplicationLabel]) [f addObject:@"lbl"];
    if (m[(__bridge id)kSecAttrAccessGroup])      [f addObject:@"grp"];
    if (m[(__bridge id)kSecValuePersistentRef])   [f addObject:@"pref"];
    if (m[(__bridge id)kSecMatchItemList])        [f addObject:@"itemlist"];
    BOOL ns = (IVNamespaceField(m) != NULL);
    NSString *sig = [NSString stringWithFormat:@"%@ %@ [%@] %@",
                     op, cls, [f componentsJoinedByString:@","], ns ? @"NS" : @"raw"];
    static NSMutableSet *seen; static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
    @synchronized (seen) {
        if ([seen containsObject:sig]) return;
        [seen addObject:sig];
    }
    IVLog(@"KC %@", sig);
}

#pragma mark - Hooked functions

// WRITE: namespace the item's field (inject a bare prefix when absent so
// field-less items are still isolated per container), then strip the prefix
// from any returned attributes.
static OSStatus iv_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    IVLogKeychainOp(@"add", attributes ? (__bridge NSDictionary *)attributes : nil);
    CFDictionaryRef q = IVCopyNamespacedQuery(attributes, YES);
    OSStatus st = orig_SecItemAdd(q, result);
    CFRelease(q);
    if (st == errSecSuccess && result && *result) {
        id stripped = IVStripResultObject((__bridge id)*result);
        if (stripped && stripped != (__bridge id)*result) {
            CFRelease(*result);
            *result = (__bridge_retained CFTypeRef)stripped;
        }
    }
    return st;
}

// READ: scope the query to THIS container without ever leaking another's item.
//
//  • Non-namespaced or explicit-ref queries: passthrough (see IVNamespaceField
//    / IVQueryHasExplicitRef) — nothing to isolate.
//  • Password read WITH its field set: prefix it and let the keychain scope the
//    match exactly; strip the prefix back out of any returned attributes.
//  • Password read WITHOUT its field (an enumeration — how an app rebuilds its
//    multi-account list on relaunch): we must NOT force an exact bare-prefix
//    match (the old bug — it could only ever match an item literally named
//    "IV:<cid>:", so items written WITH a service/server, i.e. the login/session
//    items, were invisible → logged out on reopen). Instead we discover across
//    ALL items of that class (forcing kSecReturnAttributes so each result
//    carries its field, and kSecMatchLimitAll), keep only the items whose field
//    carries THIS container's prefix, and hand them back in the caller's
//    requested shape. Finds our own items (bare-prefix AND field-keyed) and
//    still never surfaces another container's item.
static OSStatus iv_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *q = query ? (__bridge NSDictionary *)query : nil;
    IVLogKeychainOp(@"read", q);

    // Passthrough for everything we don't namespace.
    CFStringRef field = IVNamespaceField(q);
    if (!gPrefix || field == NULL || IVQueryHasExplicitRef(q)) {
        return orig_SecItemCopyMatching(query, result);
    }

    id fv = q[(__bridge id)field];
    if ([fv isKindOfClass:[NSString class]]) {
        // Field present: prefix it, keychain scopes the match, strip on return.
        CFDictionaryRef nq = IVCopyNamespacedQuery(query, NO);
        OSStatus st = orig_SecItemCopyMatching(nq, result);
        CFRelease(nq);
        if (st != errSecSuccess || !result || !*result) return st;
        id obj = (__bridge id)*result;
        if ([obj isKindOfClass:[NSArray class]]) {
            BOOL changed = NO;
            NSMutableArray *out = [NSMutableArray arrayWithCapacity:((NSArray *)obj).count];
            for (id item in (NSArray *)obj) {
                id s = IVStripResultObject(item);
                if (s != item) changed = YES;
                [out addObject:s ?: item];
            }
            if (changed) { CFRelease(*result); *result = (__bridge_retained CFTypeRef)out; }
        } else {
            id stripped = IVStripResultObject(obj);
            if (stripped && stripped != obj) { CFRelease(*result); *result = (__bridge_retained CFTypeRef)stripped; }
        }
        return st;
    }

    // Field-less enumeration: discover across all items, filter by prefix.
    BOOL wantData  = [q[(__bridge id)kSecReturnData] boolValue];
    BOOL wantAttrs = [q[(__bridge id)kSecReturnAttributes] boolValue];
    BOOL wantPRef  = [q[(__bridge id)kSecReturnPersistentRef] boolValue];
    BOOL wantRef   = [q[(__bridge id)kSecReturnRef] boolValue];
    id limit = q[(__bridge id)kSecMatchLimit];
    BOOL wantAll = [limit isEqual:(__bridge id)kSecMatchLimitAll] ||
                   ([limit isKindOfClass:[NSNumber class]] && [limit integerValue] != 1);

    NSMutableDictionary *dq = [q mutableCopy];
    dq[(__bridge id)kSecReturnAttributes] = (__bridge id)kCFBooleanTrue;   // need each field
    dq[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;      // scan every item

    CFTypeRef raw = NULL;
    OSStatus st = orig_SecItemCopyMatching((__bridge CFDictionaryRef)dq, &raw);
    if (st != errSecSuccess || !raw) {
        if (raw) CFRelease(raw);
        return (st == errSecSuccess) ? errSecItemNotFound : st;
    }

    NSMutableArray *kept = [NSMutableArray array];
    NSUInteger matchCount = 0;
    if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
        for (id item in (__bridge NSArray *)raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id s = ((NSDictionary *)item)[(__bridge id)field];
            if ([s isKindOfClass:[NSString class]] && [s hasPrefix:gPrefix]) {
                matchCount++;
                id shaped = IVReshapeItem(item, wantData, wantAttrs, wantPRef, wantRef);
                if (shaped) [kept addObject:shaped];
            }
        }
    }
    CFRelease(raw);

    if (matchCount == 0) return errSecItemNotFound;
    if (result && kept.count > 0) {
        id out = wantAll ? (id)kept : (id)kept.firstObject;
        *result = (__bridge_retained CFTypeRef)out;
    }
    return errSecSuccess;
}

// UPDATE: namespace both the match query and, if the update payload sets a new
// field value, the payload too. injectWhenAbsent=YES keeps symmetry with Add so
// a field-less item added earlier is found by the bare prefix.
static OSStatus iv_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    IVLogKeychainOp(@"update", query ? (__bridge NSDictionary *)query : nil);
    CFDictionaryRef q = IVCopyNamespacedQuery(query, YES);
    NSMutableDictionary *upd = attributesToUpdate
        ? [(__bridge NSDictionary *)attributesToUpdate mutableCopy] : nil;
    // The payload's item is the query's item, so namespace whichever field the
    // query's class uses if the payload sets a new value for it.
    CFStringRef field = IVNamespaceField(query ? (__bridge NSDictionary *)query : nil);
    if (field != NULL) {
        id newVal = upd[(__bridge id)field];
        if ([newVal isKindOfClass:[NSString class]]) upd[(__bridge id)field] = IVPrefixed(newVal);
    }
    CFDictionaryRef a = upd ? (__bridge_retained CFDictionaryRef)upd : attributesToUpdate;

    OSStatus st = orig_SecItemUpdate(q, a);
    CFRelease(q);
    if (upd) CFRelease(a);
    return st;
}

// DELETE: namespace the query (inject a bare prefix when absent). This scopes a
// field-less delete to THIS container's bare-prefix items and never touches
// other containers' field-keyed items — a deliberately safe trade-off.
static OSStatus iv_SecItemDelete(CFDictionaryRef query) {
    IVLogKeychainOp(@"delete", query ? (__bridge NSDictionary *)query : nil);
    CFDictionaryRef q = IVCopyNamespacedQuery(query, YES);
    OSStatus st = orig_SecItemDelete(q);
    CFRelease(q);
    return st;
}

#pragma mark - Raw (un-hooked) keychain access for maintenance

// Purge/enumeration helpers must reach the REAL keychain functions, bypassing
// our own namespacing. When hooks are installed (active non-default container)
// the saved originals are non-NULL; otherwise (default container / hooks never
// bound) fall back to the real Security symbols directly.
static OSStatus IVRawCopyMatching(CFDictionaryRef q, CFTypeRef *r) {
    return orig_SecItemCopyMatching ? orig_SecItemCopyMatching(q, r) : SecItemCopyMatching(q, r);
}
static OSStatus IVRawDelete(CFDictionaryRef q) {
    return orig_SecItemDelete ? orig_SecItemDelete(q) : SecItemDelete(q);
}

#pragma mark - Install

@implementation IVKeychainHook

+ (BOOL)installWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) {
        IVLog(@"Keychain: default container — real keychain passthrough (no hooks)");
        return YES;   // intentional no-op for the default container
    }
    if (gPrefix) {
        IVLog(@"Keychain: hooks already installed (prefix=%@)", gPrefix);
        return YES;
    }
    gPrefix = [prefix copy];

    struct rebinding rebindings[] = {
        {"SecItemAdd",          (void *)iv_SecItemAdd,          (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", (void *)iv_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate",       (void *)iv_SecItemUpdate,       (void **)&orig_SecItemUpdate},
        {"SecItemDelete",       (void *)iv_SecItemDelete,       (void **)&orig_SecItemDelete},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    if (rc != 0) {
        IVErr(@"Keychain: rebind_symbols failed rc=%d (prefix=%@) — isolation NOT active", rc, gPrefix);
        gPrefix = nil;   // no live prefix: never namespace with hooks that didn't bind
        return NO;
    }
    IVLog(@"Keychain: hooks installed, prefix=%@", gPrefix);
    return YES;
}

// Delete every namespaced password item whose service/server carries `prefix`.
// Used on container remove (prefix "IV:<cid>:") and global reset (prefix "IV:")
// so a wiped container leaves no orphan login/session material behind in the
// shared keychain. Enumerates both password classes via the RAW functions (so
// our own namespacing never re-scopes the sweep), matches on either namespace
// field, and deletes by persistent ref — an exact, class-agnostic delete that
// can only hit the one item we already matched. Never touches un-prefixed real
// items (the default container's own login). Returns the count deleted.
+ (NSInteger)purgeItemsWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) return 0;
    NSInteger deleted = 0;
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecClassInternetPassword ];
    for (id cls in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass:               cls,
                             (__bridge id)kSecMatchLimit:          (__bridge id)kSecMatchLimitAll,
                             (__bridge id)kSecReturnAttributes:    (__bridge id)kCFBooleanTrue,
                             (__bridge id)kSecReturnPersistentRef: (__bridge id)kCFBooleanTrue };
        CFTypeRef raw = NULL;
        OSStatus st = IVRawCopyMatching((__bridge CFDictionaryRef)q, &raw);
        if (st != errSecSuccess || !raw) { if (raw) CFRelease(raw); continue; }
        if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in (__bridge NSArray *)raw) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                id svc = item[(__bridge id)kSecAttrService];
                id srv = item[(__bridge id)kSecAttrServer];
                BOOL match = ([svc isKindOfClass:[NSString class]] && [svc hasPrefix:prefix]) ||
                             ([srv isKindOfClass:[NSString class]] && [srv hasPrefix:prefix]);
                if (!match) continue;
                id pref = item[(__bridge id)kSecValuePersistentRef];
                if (!pref) continue;
                NSDictionary *del = @{ (__bridge id)kSecValuePersistentRef: pref };
                if (IVRawDelete((__bridge CFDictionaryRef)del) == errSecSuccess) deleted++;
            }
        }
        CFRelease(raw);
    }
    IVLog(@"Keychain: purged %ld item(s) with prefix=%@", (long)deleted, prefix);
    return deleted;
}

// Count (without deleting) namespaced password items whose service/server begins
// with `prefix`. Used to VERIFY a purge actually cleared everything — a non-zero
// residue after resetAll means the reset only partially wiped credentials and
// must be reported honestly, not silently claimed as success.
+ (NSInteger)countItemsWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) return 0;
    NSInteger n = 0;
    NSArray *classes = @[ (__bridge id)kSecClassGenericPassword,
                          (__bridge id)kSecClassInternetPassword ];
    for (id cls in classes) {
        NSDictionary *q = @{ (__bridge id)kSecClass:            cls,
                             (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitAll,
                             (__bridge id)kSecReturnAttributes: (__bridge id)kCFBooleanTrue };
        CFTypeRef raw = NULL;
        OSStatus st = IVRawCopyMatching((__bridge CFDictionaryRef)q, &raw);
        if (st != errSecSuccess || !raw) { if (raw) CFRelease(raw); continue; }
        if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in (__bridge NSArray *)raw) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                id svc = item[(__bridge id)kSecAttrService];
                id srv = item[(__bridge id)kSecAttrServer];
                if (([svc isKindOfClass:[NSString class]] && [svc hasPrefix:prefix]) ||
                    ([srv isKindOfClass:[NSString class]] && [srv hasPrefix:prefix])) n++;
            }
        }
        CFRelease(raw);
    }
    return n;
}

@end
