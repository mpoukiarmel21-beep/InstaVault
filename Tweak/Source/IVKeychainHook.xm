#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <substrate.h>
#import "IVContainer.h"
#import "IVContainerManager.h"

static NSMutableDictionary *modQ(NSDictionary *q) {
    IVContainer *a=[IVContainerManager shared].active;
    if(!a) return [q mutableCopy];
    NSMutableDictionary *m=[q mutableCopy];
    NSString *p=[NSString stringWithFormat:@"IV_%@_",a.cid];
    if(m[(__bridge id)kSecAttrService])m[(__bridge id)kSecAttrService]=[p stringByAppendingString:m[(__bridge id)kSecAttrService]];
    if(m[(__bridge id)kSecAttrAccount])m[(__bridge id)kSecAttrAccount]=[p stringByAppendingString:m[(__bridge id)kSecAttrAccount]];
    return m;
}

static OSStatus (*orig_Add)(CFDictionaryRef, CFTypeRef *);
static OSStatus hook_Add(CFDictionaryRef q, CFTypeRef *r) {
    return orig_Add((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q), r);
}

static OSStatus (*orig_CopyMatch)(CFDictionaryRef, CFTypeRef *);
static OSStatus hook_CopyMatch(CFDictionaryRef q, CFTypeRef *r) {
    return orig_CopyMatch((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q), r);
}

static OSStatus (*orig_Update)(CFDictionaryRef, CFDictionaryRef);
static OSStatus hook_Update(CFDictionaryRef q, CFDictionaryRef a) {
    return orig_Update((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q), a);
}

static OSStatus (*orig_Delete)(CFDictionaryRef);
static OSStatus hook_Delete(CFDictionaryRef q) {
    return orig_Delete((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q));
}

%ctor {
    MSHookFunction(SecItemAdd, (void *)hook_Add, (void **)&orig_Add);
    MSHookFunction(SecItemCopyMatching, (void *)hook_CopyMatch, (void **)&orig_CopyMatch);
    MSHookFunction(SecItemUpdate, (void *)hook_Update, (void **)&orig_Update);
    MSHookFunction(SecItemDelete, (void *)hook_Delete, (void **)&orig_Delete);
    NSLog(@"[InstaVault] Keychain hook installed");
}
