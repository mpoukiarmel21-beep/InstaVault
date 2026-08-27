#import "IVKeychainHook.h"
#import "IVDiagnostics.h"
#import "vendor/fishhook/fishhook.h"
#import <Security/Security.h>

// The active container's keychain namespace prefix, e.g. "IV:<cid>:".
// nil == not in namespace mode (default container runs in HIDE mode instead).
static NSString *gPrefix = nil;

// The literal marker that begins EVERY container's namespaced field ("IV:<cid>:"
// always starts with this). The DEFAULT container installs the hooks in HIDE mode
// (gHideMode=YES, gPrefix=nil): it reads/writes the real, un-prefixed keychain but
// EXCLUDES any IV:-marked item from its reads and enumerations. Without this, the
// default container — which has no prefix to scope by — enumerated the physically
// shared keychain and surfaced every container's login items (their kSecAttrAccount
// is not namespaced), so an account the user never logged into on the default
// container appeared there after a container had been used. HIDE mode closes that.
static NSString *const kIVMarker = @"IV:";
static BOOL gHideMode = NO;

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
    if (gPrefix && [value isKindOfClass:[NSString class]] && [value hasPrefix:gPrefix]) {
        return [value substringFromIndex:gPrefix.length];
    }
    return value;   // hide mode (gPrefix nil) or unprefixed: return as-is
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

#pragma mark - Session persistence across device lock (P2a)

// Instagram's session/credential items inherit whatever kSecAttrAccessible class
// Instagram chose (or iOS's default, kSecAttrAccessibleWhenUnlocked, when the app
// sets none). Every "WhenUnlocked" variant is UNREADABLE while the device is
// locked, so when iOS relaunches Instagram in the background during a lock (push
// wake, background refresh) it cannot read the session, concludes the user is
// logged out, and tears the session down — then on return, already unlocked, the
// app still demands the password. We upgrade ONLY the lock-fragile classes to the
// matching AfterFirstUnlock class (readable while locked once the device has been
// unlocked once since boot), preserving the migratable-vs-ThisDeviceOnly intent
// and never DOWNGRADING a deliberately stricter policy. Applied on Add and Update
// in BOTH modes, so the real (default) login persists across lock too.
static void IVUpgradeAccessibilityInPlace(NSMutableDictionary *m) {
    id acc = m[(__bridge id)kSecAttrAccessible];
    if (acc == nil) {
        // No class set → iOS defaults to (migratable) WhenUnlocked → lock-fragile.
        m[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    } else if ([acc isEqual:(__bridge id)kSecAttrAccessibleWhenUnlocked]) {
        m[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    } else if ([acc isEqual:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) {
        m[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    }
    // AfterFirstUnlock*, WhenPasscodeSetThisDeviceOnly, Always*: left untouched —
    // already lock-survivable, or a deliberate stricter/looser policy we must keep.
}

#pragma mark - Default-container HIDE mode (P1)

// Default-container READ. The default container has no prefix to scope by, so it
// reads the real, un-prefixed keychain — but it must NEVER surface a container's
// IV:-marked item. A field-present exact read can't match one (its field value is
// "IV:<cid>:<value>", not "<value>"), so pass it straight through. A field-LESS
// enumeration would otherwise return every container's items too: discover across
// the class, DROP any IV:-marked item, and hand back only the real items in the
// caller's requested shape.
static OSStatus IVHideModeCopyMatching(NSDictionary *q, CFStringRef field, CFTypeRef *result) {
    id fv = q[(__bridge id)field];
    if ([fv isKindOfClass:[NSString class]]) {
        return orig_SecItemCopyMatching((__bridge CFDictionaryRef)q, result);   // exact real read
    }
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
    if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
        for (id item in (__bridge NSArray *)raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id s = ((NSDictionary *)item)[(__bridge id)field];
            if ([s isKindOfClass:[NSString class]] && [s hasPrefix:kIVMarker]) continue;  // hide container item
            id shaped = IVReshapeItem(item, wantData, wantAttrs, wantPRef, wantRef);
            if (shaped) [kept addObject:shaped];
        }
    }
    CFRelease(raw);
    if (kept.count == 0) return errSecItemNotFound;
    if (result) {
        id out = wantAll ? (id)kept : (id)kept.firstObject;
        *result = (__bridge_retained CFTypeRef)out;
    }
    return errSecSuccess;
}

// Default-container class-wide DELETE (field-less). A field-present delete targets
// a real item (IV: items differ by field value, untouched) and passes through; a
// class-wide delete would otherwise wipe every container's items too. Enumerate
// and delete ONLY the real, un-marked items, leaving every container's IV: items
// intact.
static OSStatus IVHideModeDeleteAllRealForClass(NSDictionary *q, CFStringRef field) {
    NSMutableDictionary *dq = [q mutableCopy];
    dq[(__bridge id)kSecReturnAttributes]    = (__bridge id)kCFBooleanTrue;
    dq[(__bridge id)kSecReturnPersistentRef] = (__bridge id)kCFBooleanTrue;
    dq[(__bridge id)kSecMatchLimit]          = (__bridge id)kSecMatchLimitAll;
    [dq removeObjectForKey:(__bridge id)kSecReturnData];
    [dq removeObjectForKey:(__bridge id)kSecReturnRef];

    CFTypeRef raw = NULL;
    OSStatus st = orig_SecItemCopyMatching((__bridge CFDictionaryRef)dq, &raw);
    if (st != errSecSuccess || !raw) { if (raw) CFRelease(raw); return st; }
    BOOL any = NO, allOK = YES;
    if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
        for (NSDictionary *item in (__bridge NSArray *)raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id s = item[(__bridge id)field];
            if ([s isKindOfClass:[NSString class]] && [s hasPrefix:kIVMarker]) continue;  // keep container item
            id pref = item[(__bridge id)kSecValuePersistentRef];
            if (!pref) continue;
            any = YES;
            NSDictionary *del = @{ (__bridge id)kSecValuePersistentRef: pref };
            if (orig_SecItemDelete((__bridge CFDictionaryRef)del) != errSecSuccess) allOK = NO;
        }
    }
    CFRelease(raw);
    if (!any) return errSecItemNotFound;
    return allOK ? errSecSuccess : errSecItemNotFound;
}

#pragma mark - Hooked functions

// WRITE: upgrade the item's accessibility so the session survives device lock
// (P2a), then — namespace mode — scope the item to this container (injecting a
// bare prefix when the field is absent) and strip the prefix from any returned
// attributes. In hide/default mode the item is written to the real keychain as-is
// (only the accessibility upgrade applies).
static OSStatus iv_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSDictionary *orig = attributes ? (__bridge NSDictionary *)attributes : nil;
    IVLogKeychainOp(@"add", orig);
    NSMutableDictionary *m = orig ? [orig mutableCopy] : [NSMutableDictionary new];
    IVUpgradeAccessibilityInPlace(m);                                     // P2a: survive device lock
    CFDictionaryRef q = gPrefix ? IVCopyNamespacedQuery((__bridge CFDictionaryRef)m, YES)
                                : (__bridge_retained CFDictionaryRef)m;   // hide/default: real write
    OSStatus st = orig_SecItemAdd(q, result);
    CFRelease(q);
    if (gPrefix && st == errSecSuccess && result && *result) {
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

    // Passthrough for everything we don't namespace / hide, ref-keyed queries, or
    // when neither mode is active.
    CFStringRef field = IVNamespaceField(q);
    if (field == NULL || IVQueryHasExplicitRef(q) || (!gPrefix && !gHideMode)) {
        return orig_SecItemCopyMatching(query, result);
    }

    // Default container: read the real keychain but never surface a container item.
    if (gHideMode) {
        return IVHideModeCopyMatching(q, field, result);
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

// UPDATE: upgrade the payload's accessibility so the session survives lock (P2a),
// then — namespace mode — namespace both the match query and, if the payload sets
// a new field value, the payload too (injectWhenAbsent=YES keeps symmetry with
// Add). In hide/default mode the (accessibility-upgraded) update is applied to the
// real keychain as-is.
static OSStatus iv_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSDictionary *qd = query ? (__bridge NSDictionary *)query : nil;
    IVLogKeychainOp(@"update", qd);
    NSMutableDictionary *upd = attributesToUpdate
        ? [(__bridge NSDictionary *)attributesToUpdate mutableCopy] : [NSMutableDictionary new];
    IVUpgradeAccessibilityInPlace(upd);                                   // P2a: survive device lock

    if (!gPrefix) {   // hide/default: match real items, apply the upgraded payload
        return orig_SecItemUpdate(query, (__bridge CFDictionaryRef)upd);
    }

    CFDictionaryRef q = IVCopyNamespacedQuery(query, YES);
    // The payload's item is the query's item, so namespace whichever field the
    // query's class uses if the payload sets a new value for it.
    CFStringRef field = IVNamespaceField(qd);
    if (field != NULL) {
        id newVal = upd[(__bridge id)field];
        if ([newVal isKindOfClass:[NSString class]]) upd[(__bridge id)field] = IVPrefixed(newVal);
    }
    OSStatus st = orig_SecItemUpdate(q, (__bridge CFDictionaryRef)upd);
    CFRelease(q);
    return st;
}

// DELETE: namespace mode scopes a field-less delete to THIS container's
// bare-prefix items and never touches other containers' field-keyed items. Hide/
// default mode passes a field-present (real-item) delete through, but for a
// class-wide (field-less) delete removes ONLY the real, un-marked items so a
// default-container wipe can never nuke a container's login.
static OSStatus iv_SecItemDelete(CFDictionaryRef query) {
    NSDictionary *qd = query ? (__bridge NSDictionary *)query : nil;
    IVLogKeychainOp(@"delete", qd);

    if (gHideMode) {
        CFStringRef field = IVNamespaceField(qd);
        if (field == NULL || IVQueryHasExplicitRef(qd) ||
            [qd[(__bridge id)field] isKindOfClass:[NSString class]]) {
            return orig_SecItemDelete(query);   // targets a real item (or non-password class)
        }
        return IVHideModeDeleteAllRealForClass(qd, field);
    }
    if (!gPrefix) return orig_SecItemDelete(query);

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

// Rebind the four SecItem* symbols to our hooks. Both modes (namespace + hide)
// install the SAME hooks; the mode flags (gPrefix / gHideMode) decide behavior.
static BOOL IVBindKeychainHooks(void) {
    struct rebinding rebindings[] = {
        {"SecItemAdd",          (void *)iv_SecItemAdd,          (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", (void *)iv_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate",       (void *)iv_SecItemUpdate,       (void **)&orig_SecItemUpdate},
        {"SecItemDelete",       (void *)iv_SecItemDelete,       (void **)&orig_SecItemDelete},
    };
    return rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0])) == 0;
}

@implementation IVKeychainHook

+ (BOOL)installWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) {
        IVLog(@"Keychain: empty prefix — use installDefaultHideMode for the default container");
        return YES;   // not the namespace path; default container installs hide mode
    }
    if (gPrefix) {
        IVLog(@"Keychain: hooks already installed (prefix=%@)", gPrefix);
        return YES;
    }
    if (gHideMode) {
        IVErr(@"Keychain: hide mode active — cannot switch to namespace mode in-process");
        return NO;
    }
    gPrefix = [prefix copy];
    if (!IVBindKeychainHooks()) {
        IVErr(@"Keychain: rebind_symbols failed (prefix=%@) — isolation NOT active", gPrefix);
        gPrefix = nil;   // no live prefix: never namespace with hooks that didn't bind
        return NO;
    }
    IVLog(@"Keychain: hooks installed, prefix=%@", gPrefix);
    return YES;
}

// Install the hooks in HIDE mode for the DEFAULT container: the real keychain is
// read/written un-prefixed, but every IV:-marked (container) item is excluded from
// reads, enumerations, and class-wide deletes. This is what stops a container's
// account from appearing in — or being clobbered by — the default container.
// Best-effort: a bind failure just leaves the prior passthrough behavior (a
// possible leak, never a crash), so a failure here must NOT block launch.
+ (BOOL)installDefaultHideMode {
    if (gPrefix) {
        IVErr(@"Keychain: namespace mode active — cannot install hide mode");
        return NO;
    }
    if (gHideMode) return YES;
    if (!IVBindKeychainHooks()) {
        IVErr(@"Keychain: rebind_symbols failed — default hide mode NOT active (real keychain passthrough)");
        return NO;
    }
    gHideMode = YES;
    IVLog(@"Keychain: DEFAULT hide mode installed (real keychain minus all IV: items)");
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
