#import "IVKeychainHook.h"
#import "IVDiagnostics.h"
#import "vendor/fishhook/fishhook.h"
#import <Security/Security.h>

// The active container's keychain namespace prefix, e.g. "IV:<cid>:".
// nil == not in namespace mode (default container runs in HIDE mode instead).
static NSString *gPrefix = nil;

// The literal marker that begins EVERY container's namespaced field ("IV:<cid>:"
// always starts with this) — on a service/server STRING for passwords, and on the
// application-tag CFDATA for keys. The DEFAULT container installs the hooks in HIDE
// mode (gHideMode=YES, gPrefix=nil): it reads/writes the real, un-prefixed keychain
// but EXCLUDES any IV:-marked item from its reads, enumerations, and class-wide
// deletes. Without this, the default container — which has no prefix to scope by —
// enumerated the physically shared keychain and surfaced every container's items
// (their kSecAttrAccount is not namespaced), so an account the user never logged
// into on the default container appeared there after a container had been used, and
// a container's device key could be swept by a default-container class delete. HIDE
// mode closes that.
static NSString *const kIVMarker = @"IV:";
static BOOL gHideMode = NO;

// Saved originals (filled by fishhook).
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;
static SecKeyRef (*orig_SecKeyCreateRandomKey)(CFDictionaryRef, CFErrorRef *) = NULL;

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

#pragma mark - Data-prefix helpers (kSecClassKey application-tag)

// kSecClassKey items are keyed by kSecAttrApplicationTag, which is CFData (opaque
// app-chosen bytes), NOT a string. So the same per-container namespacing the
// password path applies to a service/server STRING must be applied to the tag as
// raw BYTES: we prepend gPrefix's UTF-8 bytes. This is what stops the device
// keypair — Meta's strongest cross-container, survives-deletion fingerprint —
// from being shared by every container: each container now provisions and reads
// its OWN key, and a deleted container's key is purge-matchable (see below).
static NSData *IVPrefixDataBytes(void) {
    return [gPrefix dataUsingEncoding:NSUTF8StringEncoding];
}

static BOOL IVIsTagField(CFStringRef field) {
    return field != NULL && CFEqual(field, kSecAttrApplicationTag);
}

static BOOL IVDataHasNamespace(NSData *value, NSData *prefix) {
    return [value isKindOfClass:[NSData class]] && value.length >= prefix.length &&
           memcmp(value.bytes, prefix.bytes, prefix.length) == 0;
}

static NSData *IVPrefixedData(NSData *value) {
    NSData *p = IVPrefixDataBytes();
    if (![value isKindOfClass:[NSData class]]) return p;   // no tag -> bare namespace
    if (IVDataHasNamespace(value, p)) return value;        // already prefixed (idempotent)
    NSMutableData *out = [p mutableCopy];
    [out appendData:value];
    return out;
}

static NSData *IVStrippedData(NSData *value) {
    if (!gPrefix) return value;   // hide mode (no prefix): nothing to strip
    NSData *p = IVPrefixDataBytes();
    if (IVDataHasNamespace(value, p)) {
        return [value subdataWithRange:NSMakeRange(p.length, value.length - p.length)];
    }
    return value;
}

// The keychain primary-key attribute we namespace for a query's class:
//   • generic-password  -> kSecAttrService        (the service is a primary key)
//   • internet-password -> kSecAttrServer         (the host/server is primary)
//   • key               -> kSecAttrApplicationTag (app's opaque key label, CFData)
// Any other class (certificates, identities) returns NULL and passes through
// untouched: those have no single app-controlled primary key we can safely
// namespace, so injecting one matches nothing on read and is rejected on write —
// it would only corrupt a legitimate query without ever isolating anything.
//
// Namespacing BOTH password classes (not just generic-password, as the first
// cut did) is what stops one container's login from clobbering another's: an
// app that keeps any session material in an internet-password item used to
// SHARE that item across every container (last writer wins), so logging into a
// 2nd account and returning to the 1st found the 2nd's shared item and forced a
// re-login. Isolating kSecAttrServer too closes that leak; it is a strict
// superset — a no-op for apps that use no internet-password items.
//
// Namespacing kSecClassKey by kSecAttrApplicationTag closes the DEVICE-FINGERPRINT
// leak: FBSDK/Meta persist a device keypair in the keychain that was previously
// (a) SHARED by every container — not tag-namespaced — and (b) NOT wiped on
// container deletion (purge covered only password classes), so Meta could
// correlate every account attempt back to one physical device and trace even
// containers the user had already deleted (the selfie/multi-account check). It is
// again a strict superset — a no-op for apps that store no tagged keys.
static CFStringRef IVNamespaceField(NSDictionary *m) {
    id cls = m[(__bridge id)kSecClass];
    if (cls == nil) return NULL;
    if ([cls isEqual:(__bridge id)kSecClassGenericPassword])  return kSecAttrService;
    if ([cls isEqual:(__bridge id)kSecClassInternetPassword]) return kSecAttrServer;
    if ([cls isEqual:(__bridge id)kSecClassKey])              return kSecAttrApplicationTag;
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
    if (IVIsTagField(field)) {
        // kSecClassKey: the tag value is CFData — prefix its bytes.
        if ([val isKindOfClass:[NSData class]]) {
            m[(__bridge id)field] = IVPrefixedData(val);
        } else if (injectWhenAbsent) {
            m[(__bridge id)field] = IVPrefixDataBytes();
        }
    } else {
        // password classes: the service/server value is a string.
        if ([val isKindOfClass:[NSString class]]) {
            m[(__bridge id)field] = IVPrefixed(val);
        } else if (injectWhenAbsent) {
            m[(__bridge id)field] = gPrefix;
        }
    }
    return (__bridge_retained CFDictionaryRef)m;
}

// Strip our prefix from whichever namespaceable field a returned attribute dict
// carries (only one is ever present per item), rewriting it to the app-visible
// value: a service/server STRING for passwords, the application-tag CFDATA for
// keys.
static void IVStripFieldsInPlace(NSMutableDictionary *m) {
    id svc = m[(__bridge id)kSecAttrService];
    if ([svc isKindOfClass:[NSString class]]) m[(__bridge id)kSecAttrService] = IVStripped(svc);
    id srv = m[(__bridge id)kSecAttrServer];
    if ([srv isKindOfClass:[NSString class]]) m[(__bridge id)kSecAttrServer] = IVStripped(srv);
    id tag = m[(__bridge id)kSecAttrApplicationTag];
    if ([tag isKindOfClass:[NSData class]]) m[(__bridge id)kSecAttrApplicationTag] = IVStrippedData(tag);
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
// which item classes and key attributes Badoo touches during login WITHOUT
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

#pragma mark - Field / marker helpers

// "Field present" means the query pins the class's primary key: a service/server
// STRING for passwords, or an application-tag CFDATA for keys.
static BOOL IVFieldPresent(id fv, CFStringRef field) {
    return IVIsTagField(field) ? [fv isKindOfClass:[NSData class]]
                               : [fv isKindOfClass:[NSString class]];
}

// Is a discovered field value an IV:-marked (container) value? Matches the "IV:"
// marker on a password service/server STRING and on a key application-tag CFDATA —
// so HIDE mode can exclude a container's device key as well as its logins.
static BOOL IVValueHasMarker(id v, CFStringRef field) {
    if (IVIsTagField(field)) {
        if (![v isKindOfClass:[NSData class]]) return NO;
        static NSData *markerData; static dispatch_once_t once;
        dispatch_once(&once, ^{ markerData = [kIVMarker dataUsingEncoding:NSUTF8StringEncoding]; });
        return IVDataHasNamespace(v, markerData);
    }
    return [v isKindOfClass:[NSString class]] && [v hasPrefix:kIVMarker];
}

#pragma mark - Session persistence across device lock (P2a)

// Badoo's session/credential items inherit whatever kSecAttrAccessible class the
// app chose (or iOS's default, kSecAttrAccessibleWhenUnlocked, when it sets none).
// Every "WhenUnlocked" variant is UNREADABLE while the device is locked, so when
// iOS relaunches Badoo in the background during a lock (push wake, background
// refresh) it cannot read the session, concludes the user is logged out, and tears
// the session down — then on return, already unlocked, the app still demands the
// password. We upgrade ONLY the lock-fragile classes to the matching
// AfterFirstUnlock class (readable while locked once the device has been unlocked
// once since boot), preserving the migratable-vs-ThisDeviceOnly intent and never
// DOWNGRADING a deliberately stricter policy. Applied on Add and Update in BOTH
// modes, so the real (default) login persists across lock too.
static void IVUpgradeAccessibilityInPlace(NSMutableDictionary *m) {
    id acc = m[(__bridge id)kSecAttrAccessible];
    if (acc == nil) {
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

// HIDE-mode READ: the DEFAULT container reads the REAL, un-prefixed keychain but
// must never surface a container's (IV:-marked) item. A field-PRESENT query for
// an un-marked value can never match a marked item (their field values differ),
// so it passes straight through; a query that explicitly names an IV: value is
// hidden (errSecItemNotFound). A field-LESS enumeration is the leak that mattered:
// a bare class query returns EVERY item of the class, including every container's,
// so an account created only inside a container appeared on the default after the
// container had been used once. We discover across the class, DROP every marked
// item (string marker for passwords, CFData marker for the key tag), and reshape
// the survivors into the caller's requested return shape.
static OSStatus IVHideModeCopyMatching(CFDictionaryRef query, CFTypeRef *result, CFStringRef field) {
    NSDictionary *q = query ? (__bridge NSDictionary *)query : nil;
    id fv = q[(__bridge id)field];
    if (IVFieldPresent(fv, field)) {
        if (IVValueHasMarker(fv, field)) return errSecItemNotFound;   // hide container item
        return orig_SecItemCopyMatching(query, result);              // real item: passthrough
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
            id v = ((NSDictionary *)item)[(__bridge id)field];
            if (IVValueHasMarker(v, field)) continue;   // drop container item
            id shaped = IVReshapeItem(item, wantData, wantAttrs, wantPRef, wantRef);
            if (shaped) [kept addObject:shaped];
        }
    }
    CFRelease(raw);
    if (kept.count == 0) return errSecItemNotFound;
    if (result) *result = (__bridge_retained CFTypeRef)(wantAll ? (id)kept : (id)kept.firstObject);
    return errSecSuccess;
}

// HIDE-mode class-wide DELETE: a bare `{ class: genp }` delete from the default
// container would, un-hooked, erase EVERY item of that class — including every
// container's isolated login and device key. We enumerate the class, keep only
// the REAL (un-marked) items, and delete each by an exact persistent ref, so a
// default-container "delete all passwords" never reaches into a container.
static OSStatus IVHideModeDeleteAllRealForClass(CFDictionaryRef query, CFStringRef field) {
    NSMutableDictionary *dq = query ? [(__bridge NSDictionary *)query mutableCopy] : [NSMutableDictionary new];
    [dq removeObjectForKey:(__bridge id)kSecReturnData];
    [dq removeObjectForKey:(__bridge id)kSecReturnRef];
    dq[(__bridge id)kSecReturnAttributes]    = (__bridge id)kCFBooleanTrue;
    dq[(__bridge id)kSecReturnPersistentRef] = (__bridge id)kCFBooleanTrue;
    dq[(__bridge id)kSecMatchLimit]          = (__bridge id)kSecMatchLimitAll;

    CFTypeRef raw = NULL;
    OSStatus st = orig_SecItemCopyMatching((__bridge CFDictionaryRef)dq, &raw);
    if (st != errSecSuccess || !raw) {
        if (raw) CFRelease(raw);
        return (st == errSecSuccess) ? errSecItemNotFound : st;
    }
    NSInteger realSeen = 0, deleted = 0;
    if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
        for (NSDictionary *item in (__bridge NSArray *)raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id v = item[(__bridge id)field];
            if (IVValueHasMarker(v, field)) continue;   // keep container item
            realSeen++;
            id pref = item[(__bridge id)kSecValuePersistentRef];
            if (!pref) continue;
            NSDictionary *del = @{ (__bridge id)kSecValuePersistentRef: pref };
            if (orig_SecItemDelete((__bridge CFDictionaryRef)del) == errSecSuccess) deleted++;
        }
    }
    CFRelease(raw);
    if (realSeen == 0) return errSecItemNotFound;
    return (deleted > 0) ? errSecSuccess : errSecItemNotFound;
}

#pragma mark - Hooked functions

// WRITE: namespace the item's field (inject a bare prefix when absent so
// field-less items are still isolated per container), then strip the prefix
// from any returned attributes.
static OSStatus iv_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    IVLogKeychainOp(@"add", attributes ? (__bridge NSDictionary *)attributes : nil);

    // P2a: upgrade the item's accessibility so it survives a device lock, in BOTH
    // modes (the default/real login benefits too, not only isolated containers).
    NSMutableDictionary *m = attributes ? [(__bridge NSDictionary *)attributes mutableCopy]
                                        : [NSMutableDictionary new];
    IVUpgradeAccessibilityInPlace(m);

    if (gHideMode || !gPrefix) {
        // Default container (HIDE) or hooks-bound-without-prefix: write the REAL
        // keychain un-namespaced. No IV: marker is ever added → nothing to strip.
        return orig_SecItemAdd((__bridge CFDictionaryRef)m, result);
    }

    CFDictionaryRef q = IVCopyNamespacedQuery((__bridge CFDictionaryRef)m, YES);
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

    // Passthrough for everything we don't namespace (non-namespaceable class, or a
    // query already pinned to one exact item by an explicit reference).
    CFStringRef field = IVNamespaceField(q);
    if (field == NULL || IVQueryHasExplicitRef(q)) {
        return orig_SecItemCopyMatching(query, result);
    }
    // Default container: read the real keychain but hide every container's IV: item.
    if (gHideMode) {
        return IVHideModeCopyMatching(query, result, field);
    }
    // Hooks bound without a prefix and not in HIDE mode: nothing to isolate.
    if (!gPrefix) {
        return orig_SecItemCopyMatching(query, result);
    }

    id fv = q[(__bridge id)field];
    // "Field present" means the query pins the class's primary key: a service/
    // server STRING for passwords, or an application-tag CFDATA for keys.
    BOOL fieldPresent = IVIsTagField(field) ? [fv isKindOfClass:[NSData class]]
                                            : [fv isKindOfClass:[NSString class]];
    if (fieldPresent) {
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
    NSData *prefixData = IVIsTagField(field) ? IVPrefixDataBytes() : nil;
    if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
        for (id item in (__bridge NSArray *)raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id s = ((NSDictionary *)item)[(__bridge id)field];
            BOOL mine = prefixData ? IVDataHasNamespace(s, prefixData)
                                   : ([s isKindOfClass:[NSString class]] && [s hasPrefix:gPrefix]);
            if (mine) {
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

    // P2a: upgrade the updated item's accessibility so it survives a lock. Applied
    // to the payload in BOTH modes; a payload that set no accessibility gets the
    // AfterFirstUnlock floor, lifting a previously lock-fragile item on any update.
    NSMutableDictionary *upd = attributesToUpdate
        ? [(__bridge NSDictionary *)attributesToUpdate mutableCopy] : [NSMutableDictionary new];
    IVUpgradeAccessibilityInPlace(upd);

    if (gHideMode || !gPrefix) {
        // Default container / hooks-without-prefix: update the REAL item un-namespaced.
        return orig_SecItemUpdate(query, (__bridge CFDictionaryRef)upd);
    }

    CFDictionaryRef q = IVCopyNamespacedQuery(query, YES);
    // The payload's item is the query's item, so namespace whichever field the
    // query's class uses if the payload sets a new value for it.
    CFStringRef field = IVNamespaceField(query ? (__bridge NSDictionary *)query : nil);
    if (field != NULL) {
        id newVal = upd[(__bridge id)field];
        if (IVIsTagField(field)) {
            if ([newVal isKindOfClass:[NSData class]]) upd[(__bridge id)field] = IVPrefixedData(newVal);
        } else if ([newVal isKindOfClass:[NSString class]]) {
            upd[(__bridge id)field] = IVPrefixed(newVal);
        }
    }
    OSStatus st = orig_SecItemUpdate(q, (__bridge CFDictionaryRef)upd);
    CFRelease(q);
    return st;
}

// DELETE: namespace the query (inject a bare prefix when absent). This scopes a
// field-less delete to THIS container's bare-prefix items and never touches
// other containers' field-keyed items — a deliberately safe trade-off.
static OSStatus iv_SecItemDelete(CFDictionaryRef query) {
    NSDictionary *q = query ? (__bridge NSDictionary *)query : nil;
    IVLogKeychainOp(@"delete", q);

    if (gHideMode) {
        // Default container: a delete must never reach a container's IV: item.
        CFStringRef field = IVNamespaceField(q);
        if (field == NULL || IVQueryHasExplicitRef(q)) {
            return orig_SecItemDelete(query);   // non-namespaceable / ref-keyed: a real item
        }
        id fv = q[(__bridge id)field];
        if (IVFieldPresent(fv, field)) {
            if (IVValueHasMarker(fv, field)) return errSecItemNotFound;  // refuse a container item
            return orig_SecItemDelete(query);                            // exact real item
        }
        // Field-less class-wide delete: erase only the REAL (un-marked) items.
        return IVHideModeDeleteAllRealForClass(query, field);
    }
    if (!gPrefix) {
        return orig_SecItemDelete(query);   // hooks bound without a prefix: passthrough
    }

    CFDictionaryRef nq = IVCopyNamespacedQuery(query, YES);
    OSStatus st = orig_SecItemDelete(nq);
    CFRelease(nq);
    return st;
}

// CREATE KEY: SecKeyCreateRandomKey(kSecAttrIsPermanent) persists the new key
// through Security.framework's OWN internal SecItemAdd — a call we cannot see
// from fishhook (it never crosses the app's import table). If we only namespaced
// the READ query (SecItemCopyMatching), the stored tag would stay un-prefixed
// while the read looked for a prefixed one → the app could never find the key it
// just made and would regenerate forever, breaking login. So we namespace the
// tag HERE, at creation, before calling through — making write and read
// symmetric by construction. Namespacing only when a tag is actually present
// keeps this a no-op for ephemeral / label-only keys.
static void IVPrefixTagInDict(NSMutableDictionary *d) {
    id tag = d[(__bridge id)kSecAttrApplicationTag];
    if ([tag isKindOfClass:[NSData class]]) d[(__bridge id)kSecAttrApplicationTag] = IVPrefixedData(tag);
}

static SecKeyRef iv_SecKeyCreateRandomKey(CFDictionaryRef parameters, CFErrorRef *error) {
    if (!gPrefix || !parameters) return orig_SecKeyCreateRandomKey(parameters, error);
    NSMutableDictionary *p = [(__bridge NSDictionary *)parameters mutableCopy];
    IVPrefixTagInDict(p);   // tag may sit at the top level…
    // …or inside the private/public sub-attribute dictionaries.
    for (id sub in @[ (__bridge id)kSecPrivateKeyAttrs, (__bridge id)kSecPublicKeyAttrs ]) {
        id v = p[sub];
        if ([v isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *ms = [v mutableCopy];
            IVPrefixTagInDict(ms);
            p[sub] = ms;
        }
    }
    return orig_SecKeyCreateRandomKey((__bridge CFDictionaryRef)p, error);
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

// Does a discovered item belong to the container(s) identified by `prefix`?
// Matches a password item on its service/server STRING and a key item on its
// application-tag CFDATA — so the sweep covers both credential material and the
// per-container device key, and never touches an un-prefixed real item (the
// default container's own login / device key).
static BOOL IVItemMatchesPrefix(NSDictionary *item, NSString *prefix) {
    id svc = item[(__bridge id)kSecAttrService];
    if ([svc isKindOfClass:[NSString class]] && [svc hasPrefix:prefix]) return YES;
    id srv = item[(__bridge id)kSecAttrServer];
    if ([srv isKindOfClass:[NSString class]] && [srv hasPrefix:prefix]) return YES;
    id tag = item[(__bridge id)kSecAttrApplicationTag];
    if ([tag isKindOfClass:[NSData class]]) {
        NSData *pd = [prefix dataUsingEncoding:NSUTF8StringEncoding];
        if (IVDataHasNamespace(tag, pd)) return YES;
    }
    return NO;
}

// The keychain classes our namespacing touches: both password classes plus keys.
static NSArray *IVNamespacedClasses(void) {
    return @[ (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecClassInternetPassword,
              (__bridge id)kSecClassKey ];
}

#pragma mark - Hook binding

// Rebind the five keychain symbols ONCE, shared by both install paths (namespace
// mode for a container, HIDE mode for the default). The four SecItem* hooks and
// SecKeyCreateRandomKey read gPrefix / gHideMode at call time, so a single bind
// serves whichever mode is active. Idempotent: a second call is a no-op.
static BOOL gHooksBound = NO;
static BOOL IVBindKeychainHooks(void) {
    if (gHooksBound) return YES;
    struct rebinding rebindings[] = {
        {"SecItemAdd",            (void *)iv_SecItemAdd,            (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching",   (void *)iv_SecItemCopyMatching,   (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate",         (void *)iv_SecItemUpdate,         (void **)&orig_SecItemUpdate},
        {"SecItemDelete",         (void *)iv_SecItemDelete,         (void **)&orig_SecItemDelete},
        {"SecKeyCreateRandomKey", (void *)iv_SecKeyCreateRandomKey, (void **)&orig_SecKeyCreateRandomKey},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    if (rc != 0) {
        IVErr(@"Keychain: rebind_symbols failed rc=%d — hooks NOT bound", rc);
        return NO;
    }
    gHooksBound = YES;
    return YES;
}

#pragma mark - Install

@implementation IVKeychainHook

+ (BOOL)installWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) {
        // Empty prefix means the default container — it runs HIDE mode instead,
        // installed via +installDefaultHideMode. Keep this a benign no-op so an
        // old caller passing "" for the default still behaves.
        IVLog(@"Keychain: empty prefix — default container uses HIDE mode (installDefaultHideMode)");
        return YES;
    }
    if (gHideMode) {
        // The two modes are mutually exclusive within one process: HIDE reads the
        // real keychain, namespace mode rewrites every field. Never mix them.
        IVErr(@"Keychain: refusing prefix install — HIDE mode already active");
        return NO;
    }
    if (gPrefix) {
        IVLog(@"Keychain: hooks already installed (prefix=%@)", gPrefix);
        return YES;
    }
    gPrefix = [prefix copy];
    if (!IVBindKeychainHooks()) {
        gPrefix = nil;   // no live prefix: never namespace with hooks that didn't bind
        IVErr(@"Keychain: bind failed (prefix=%@) — isolation NOT active", prefix);
        return NO;
    }
    IVLog(@"Keychain: namespace hooks installed, prefix=%@", gPrefix);
    return YES;
}

// Default-container HIDE mode: bind the same hooks but leave gPrefix nil. The
// default then reads/writes the REAL keychain while EXCLUDING every container's
// IV:-marked item from its reads, enumerations, and class-wide deletes (P1), and
// still gets the P2a accessibility upgrade so the real login survives a lock.
// Mutually exclusive with a namespace prefix.
+ (BOOL)installDefaultHideMode {
    if (gPrefix) {
        IVErr(@"Keychain: refusing HIDE mode — namespace prefix already active (%@)", gPrefix);
        return NO;
    }
    if (gHideMode) {
        IVLog(@"Keychain: HIDE mode already active");
        return YES;
    }
    gHideMode = YES;
    if (!IVBindKeychainHooks()) {
        gHideMode = NO;   // bind failed: fall back to a plain, unhooked default
        IVErr(@"Keychain: bind failed — HIDE mode NOT active");
        return NO;
    }
    IVLog(@"Keychain: default-container HIDE mode installed (real keychain; IV: items hidden)");
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
    for (id cls in IVNamespacedClasses()) {
        NSDictionary *q = @{ (__bridge id)kSecClass:               cls,
                             (__bridge id)kSecMatchLimit:          (__bridge id)kSecMatchLimitAll,
                             (__bridge id)kSecReturnAttributes:    (__bridge id)kCFBooleanTrue,
                             (__bridge id)kSecReturnPersistentRef: (__bridge id)kCFBooleanTrue,
                             // Match iCloud-Keychain (synchronizable) items too, not only
                             // device-local ones. A query that omits kSecAttrSynchronizable
                             // defaults to non-synchronizable only, so a login token stored
                             // as synchronizable would survive the sweep (the account "ne
                             // disparaît pas toujours" after a reset). SynchronizableAny
                             // covers both; we can only ever see Badoo's own items anyway.
                             (__bridge id)kSecAttrSynchronizable:  (__bridge id)kSecAttrSynchronizableAny };
        CFTypeRef raw = NULL;
        OSStatus st = IVRawCopyMatching((__bridge CFDictionaryRef)q, &raw);
        if (st != errSecSuccess || !raw) { if (raw) CFRelease(raw); continue; }
        if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in (__bridge NSArray *)raw) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                if (!IVItemMatchesPrefix(item, prefix)) continue;
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
    for (id cls in IVNamespacedClasses()) {
        NSDictionary *q = @{ (__bridge id)kSecClass:            cls,
                             (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitAll,
                             (__bridge id)kSecReturnAttributes: (__bridge id)kCFBooleanTrue,
                             // Count synchronizable items too, so the residue check
                             // agrees with the (now SynchronizableAny) purge above.
                             (__bridge id)kSecAttrSynchronizable: (__bridge id)kSecAttrSynchronizableAny };
        CFTypeRef raw = NULL;
        OSStatus st = IVRawCopyMatching((__bridge CFDictionaryRef)q, &raw);
        if (st != errSecSuccess || !raw) { if (raw) CFRelease(raw); continue; }
        if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in (__bridge NSArray *)raw) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                if (IVItemMatchesPrefix(item, prefix)) n++;
            }
        }
        CFRelease(raw);
    }
    return n;
}

// Delete the REAL (un-namespaced) login/session material — every generic- and
// internet-password item whose service/server does NOT begin with the "IV:"
// marker. The inverse of purgeItemsWithPrefix:, this logs the PRINCIPAL / default
// account out during a global reset, leaving every container's marked item intact.
// The kSecClassKey device keypair is DELIBERATELY excluded: it is a device
// fingerprint, not a login credential, and regenerating the real device identity
// on reset would provoke a "new device" verification challenge on the real
// account. Container device keys are still wiped by purgeItemsWithPrefix: on
// container delete/reset. Uses the RAW keychain fns so HIDE-mode read filtering
// never scopes the sweep. Returns the count deleted.
+ (NSInteger)purgeRealPasswordItems {
    NSInteger deleted = 0;
    NSArray *passwordClasses = @[ (__bridge id)kSecClassGenericPassword,
                                  (__bridge id)kSecClassInternetPassword ];
    for (id cls in passwordClasses) {
        NSDictionary *q = @{ (__bridge id)kSecClass:               cls,
                             (__bridge id)kSecMatchLimit:          (__bridge id)kSecMatchLimitAll,
                             (__bridge id)kSecReturnAttributes:    (__bridge id)kCFBooleanTrue,
                             (__bridge id)kSecReturnPersistentRef: (__bridge id)kCFBooleanTrue,
                             // Match iCloud-Keychain (synchronizable) items too, not only
                             // device-local ones. A query that omits kSecAttrSynchronizable
                             // defaults to non-synchronizable only, so a login token stored
                             // as synchronizable would survive the sweep (the account "ne
                             // disparaît pas toujours" after a reset). SynchronizableAny
                             // covers both; we can only ever see Badoo's own items anyway.
                             (__bridge id)kSecAttrSynchronizable:  (__bridge id)kSecAttrSynchronizableAny };
        CFTypeRef raw = NULL;
        OSStatus st = IVRawCopyMatching((__bridge CFDictionaryRef)q, &raw);
        if (st != errSecSuccess || !raw) { if (raw) CFRelease(raw); continue; }
        if ([(__bridge id)raw isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in (__bridge NSArray *)raw) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                id svc = item[(__bridge id)kSecAttrService];
                id srv = item[(__bridge id)kSecAttrServer];
                BOOL marked = ([svc isKindOfClass:[NSString class]] && [svc hasPrefix:kIVMarker]) ||
                              ([srv isKindOfClass:[NSString class]] && [srv hasPrefix:kIVMarker]);
                if (marked) continue;   // leave every container's item untouched
                id pref = item[(__bridge id)kSecValuePersistentRef];
                if (!pref) continue;
                NSDictionary *del = @{ (__bridge id)kSecValuePersistentRef: pref };
                if (IVRawDelete((__bridge CFDictionaryRef)del) == errSecSuccess) deleted++;
            }
        }
        CFRelease(raw);
    }
    IVLog(@"Keychain: purged %ld REAL password item(s) (principal logout)", (long)deleted);
    return deleted;
}

@end
