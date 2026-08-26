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

static NSString *IVPrefixed(NSString *service) {
    if (![service isKindOfClass:[NSString class]]) return gPrefix;   // no service -> bare namespace
    if ([service hasPrefix:gPrefix]) return service;                 // already prefixed
    return [gPrefix stringByAppendingString:service];
}

static NSString *IVStripped(NSString *service) {
    if ([service isKindOfClass:[NSString class]] && [service hasPrefix:gPrefix]) {
        return [service substringFromIndex:gPrefix.length];
    }
    return service;
}

// YES only for generic-password queries — the ONE keychain class where
// kSecAttrService is a valid primary key. Injecting a service into any other
// class (internet passwords, keys, certificates, identities) matches nothing on
// read and is ignored/rejected on write, i.e. it would BREAK a legitimate
// Instagram query in a non-default container without ever isolating anything.
// So we namespace generic-password items (where Instagram keeps its account and
// session state) and pass every other class straight through, un-isolated. This
// is strictly safer than blanket-injecting: for non-generic classes the old
// behaviour could not isolate them anyway — it only corrupted the query.
static BOOL IVQueryIsGenericPassword(NSDictionary *m) {
    id cls = m[(__bridge id)kSecClass];
    return cls != nil && [cls isEqual:(__bridge id)kSecClassGenericPassword];
}

// A query that identifies its item by an explicit reference — a persistent ref
// (kSecValuePersistentRef) or an explicit item list (kSecMatchItemList) — already
// targets one exact item. That reference could only have been handed back by a
// prior query that WAS namespaced, so it is container-safe as-is. Forcing a
// kSecAttrService constraint onto such a query is actively harmful: the stored
// item's service is the *namespaced* string, not the bare prefix we would inject,
// so the added constraint filters the referenced item straight out and the lookup
// fails. Detect these and pass the query through untouched.
static BOOL IVQueryHasExplicitRef(NSDictionary *m) {
    return m[(__bridge id)kSecValuePersistentRef] != nil ||
           m[(__bridge id)kSecMatchItemList] != nil;
}

// Returns a retained copy of `query` with kSecAttrService namespaced.
// When `injectWhenAbsent` is YES and the query has no service, a bare prefix is
// set — used by Add/Update/Delete so a service-less item is still isolated per
// container. Reads never call this with a missing service (serviceless
// enumeration is handled specially in iv_SecItemCopyMatching). Non-generic or
// ref-keyed queries are returned unchanged (see the predicates above).
static CFDictionaryRef IVCopyNamespacedQuery(CFDictionaryRef query, BOOL injectWhenAbsent) {
    NSMutableDictionary *m = query ? [(__bridge NSDictionary *)query mutableCopy] : [NSMutableDictionary new];
    if (!IVQueryIsGenericPassword(m) || IVQueryHasExplicitRef(m)) {
        return (__bridge_retained CFDictionaryRef)m;   // non-generic OR ref-keyed: leave untouched
    }
    id svc = m[(__bridge id)kSecAttrService];
    if ([svc isKindOfClass:[NSString class]]) {
        m[(__bridge id)kSecAttrService] = IVPrefixed(svc);
    } else if (injectWhenAbsent) {
        m[(__bridge id)kSecAttrService] = gPrefix;
    }
    return (__bridge_retained CFDictionaryRef)m;
}

// Rewrites service in a returned attribute dictionary back to the app-visible
// (un-prefixed) value. Returns a retained CF dict, or NULL to keep original.
static id IVStripResultObject(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [obj mutableCopy];
        id svc = d[(__bridge id)kSecAttrService];
        if ([svc isKindOfClass:[NSString class]]) d[(__bridge id)kSecAttrService] = IVStripped(svc);
        return d;
    }
    return obj;
}

// Reshape one discovered attribute dict back into the exact return shape the
// caller's ORIGINAL query asked for. We force kSecReturnAttributes on the
// discovery query (so every result carries its kSecAttrService for prefix
// filtering); this undoes that, handing back raw data / a persistent-ref / a
// value dict / the attribute dict as appropriate, with our prefix stripped.
// Returns nil when the caller requested no return payload at all.
static id IVReshapeItem(NSDictionary *d, BOOL wantData, BOOL wantAttrs,
                        BOOL wantPRef, BOOL wantRef) {
    NSMutableDictionary *m = [d mutableCopy];
    id svc = m[(__bridge id)kSecAttrService];
    if ([svc isKindOfClass:[NSString class]]) m[(__bridge id)kSecAttrService] = IVStripped(svc);

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

#pragma mark - Hooked functions

// WRITE: namespace the item's service (inject a bare prefix when absent so
// service-less items are still isolated per container), then strip the prefix
// from any returned attributes.
static OSStatus iv_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
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
//  • Non-generic-password or explicit-ref queries: passthrough (see the query
//    predicates above) — nothing to isolate.
//  • Generic-password read WITH a service: prefix it and let the keychain scope
//    the match exactly; strip the prefix back out of any returned attributes.
//  • Generic-password read WITHOUT a service (an enumeration — how Instagram
//    rebuilds its multi-account list on relaunch): we must NOT force an exact
//    bare-prefix service match (the old bug — it could only ever match an item
//    literally named "IV:<cid>:", so items written WITH a service, i.e. the
//    login/session items, were invisible → logged out on reopen). Instead we
//    discover across ALL services (forcing kSecReturnAttributes so each result
//    carries its service, and kSecMatchLimitAll), keep only the items whose
//    service carries THIS container's prefix, and hand them back in the caller's
//    requested shape. This finds our own items (bare-prefix AND service-keyed)
//    and still never surfaces another container's item.
static OSStatus iv_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *q = query ? (__bridge NSDictionary *)query : nil;

    // Passthrough for everything we don't namespace.
    if (!gPrefix || !IVQueryIsGenericPassword(q) || IVQueryHasExplicitRef(q)) {
        return orig_SecItemCopyMatching(query, result);
    }

    id svc = q[(__bridge id)kSecAttrService];
    if ([svc isKindOfClass:[NSString class]]) {
        // Service present: prefix it, keychain scopes the match, strip on return.
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

    // Serviceless enumeration: discover across all services, filter by prefix.
    BOOL wantData  = [q[(__bridge id)kSecReturnData] boolValue];
    BOOL wantAttrs = [q[(__bridge id)kSecReturnAttributes] boolValue];
    BOOL wantPRef  = [q[(__bridge id)kSecReturnPersistentRef] boolValue];
    BOOL wantRef   = [q[(__bridge id)kSecReturnRef] boolValue];
    id limit = q[(__bridge id)kSecMatchLimit];
    BOOL wantAll = [limit isEqual:(__bridge id)kSecMatchLimitAll] ||
                   ([limit isKindOfClass:[NSNumber class]] && [limit integerValue] != 1);

    NSMutableDictionary *dq = [q mutableCopy];
    dq[(__bridge id)kSecReturnAttributes] = (__bridge id)kCFBooleanTrue;   // need each service
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
            id s = ((NSDictionary *)item)[(__bridge id)kSecAttrService];
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
// service, the payload too. injectWhenAbsent=YES keeps symmetry with Add so a
// service-less item added earlier is found by the bare prefix.
static OSStatus iv_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    CFDictionaryRef q = IVCopyNamespacedQuery(query, YES);
    NSMutableDictionary *upd = attributesToUpdate
        ? [(__bridge NSDictionary *)attributesToUpdate mutableCopy] : nil;
    id newSvc = upd[(__bridge id)kSecAttrService];
    if ([newSvc isKindOfClass:[NSString class]]) upd[(__bridge id)kSecAttrService] = IVPrefixed(newSvc);
    CFDictionaryRef a = upd ? (__bridge_retained CFDictionaryRef)upd : attributesToUpdate;

    OSStatus st = orig_SecItemUpdate(q, a);
    CFRelease(q);
    if (upd) CFRelease(a);
    return st;
}

// DELETE: namespace the query (inject a bare prefix when absent). This scopes a
// service-less delete to THIS container's bare-prefix items and never touches
// other containers' service-keyed items — a deliberately safe trade-off.
static OSStatus iv_SecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef q = IVCopyNamespacedQuery(query, YES);
    OSStatus st = orig_SecItemDelete(q);
    CFRelease(q);
    return st;
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

@end
