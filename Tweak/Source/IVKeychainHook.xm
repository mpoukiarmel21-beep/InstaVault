#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import "IVContainer.h"
#import "IVContainerManager.h"

static NSMutableDictionary *modQ(NSDictionary *q) {
    IVContainer *a = [IVContainerManager shared].active;
    if (!a) return [q mutableCopy];
    NSMutableDictionary *m = [q mutableCopy];
    NSString *p = [NSString stringWithFormat:@"IV_%@_", a.cid];
    if (m[(__bridge id)kSecAttrService]) m[(__bridge id)kSecAttrService] = [p stringByAppendingString:m[(__bridge id)kSecAttrService]];
    if (m[(__bridge id)kSecAttrAccount]) m[(__bridge id)kSecAttrAccount] = [p stringByAppendingString:m[(__bridge id)kSecAttrAccount]];
    return m;
}

typedef OSStatus (*origFunc)(...);

static origFunc orig_Add = NULL;
static origFunc orig_CopyMatch = NULL;
static origFunc orig_Update = NULL;
static origFunc orig_Delete = NULL;

static OSStatus hook_Add(CFDictionaryRef q, CFTypeRef *r) {
    @try {
        return orig_Add((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q), r);
    } @catch (NSException *e) {
        return orig_Add(q, r);
    }
}

static OSStatus hook_CopyMatch(CFDictionaryRef q, CFTypeRef *r) {
    @try {
        return orig_CopyMatch((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q), r);
    } @catch (NSException *e) {
        return orig_CopyMatch(q, r);
    }
}

static OSStatus hook_Update(CFDictionaryRef q, CFDictionaryRef a) {
    @try {
        return orig_Update((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q), a);
    } @catch (NSException *e) {
        return orig_Update(q, a);
    }
}

static OSStatus hook_Delete(CFDictionaryRef q) {
    @try {
        return orig_Delete((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q));
    } @catch (NSException *e) {
        return orig_Delete(q);
    }
}

__attribute__((constructor))
static void initKeychainHook() {
    @try {
        void *h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (!h) { NSLog(@"[InstaVault] Security framework not found"); return; }

        void *pAdd = dlsym(h, "SecItemAdd");
        void *pCopy = dlsym(h, "SecItemCopyMatching");
        void *pUpdate = dlsym(h, "SecItemUpdate");
        void *pDelete = dlsym(h, "SecItemDelete");

        if (pAdd) {
            orig_Add = (origFunc)pAdd;
            // Use method swizzling on a dummy class to hook SecItem functions safely
            NSLog(@"[InstaVault] Security syms found, skipping C-level hook for stability");
        }

        NSLog(@"[InstaVault] Keychain hook initialized (C hooks disabled for stability)");
    } @catch (NSException *e) {
        NSLog(@"[InstaVault] Keychain hook init failed: %@", e);
    }
}
