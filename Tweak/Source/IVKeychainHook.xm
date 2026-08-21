#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import "IVContainerManager.h"

// Per-container Keychain isolation: namespace all keychain queries by container ID

static NSString *IVKeychainPrefix(void) {
    IVContainer *active = [IVContainerManager shared].active;
    return active ? [NSString stringWithFormat:@"InstaVault.%@.", active.cid] : @"InstaVault.global.";
}

static CFStringRef IVPrefixQuery(CFStringRef key) {
    NSString *prefixed = [IVKeychainPrefix() stringByAppendingString:(__bridge NSString *)key];
    return (__bridge_retained CFStringRef)prefixed;
}

static CFDictionaryRef IVProcessQuery(CFDictionaryRef query) {
    if (!query) return query;
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:(__bridge NSDictionary *)query];
    
    // Namespace generic, label, account, service, and access group
    if (m[kSecAttrGeneric as NSString]) m[kSecAttrGeneric as NSString] = IVPrefixQuery(m[kSecAttrGeneric as NSString]);
    if (m[kSecAttrLabel as NSString]) m[kSecAttrLabel as NSString] = IVPrefixQuery(m[kSecAttrLabel as NSString]);
    if (m[kSecAttrAccount as NSString]) m[kSecAttrAccount as NSString] = IVPrefixQuery(m[kSecAttrAccount as NSString]);
    if (m[kSecAttrService as NSString]) m[kSecAttrService as NSString] = IVPrefixQuery(m[kSecAttrService as NSString]);
    if (m[kSecAttrAccessGroup as NSString]) m[kSecAttrAccessGroup as NSString] = IVPrefixQuery(m[kSecAttrAccessGroup as NSString]);
    
    return (__bridge_retained CFDictionaryRef)m;
}

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus hooked_SecItemAdd(CFDictionaryRef query, CFTypeRef *result) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) query = IVProcessQuery(query);
    return orig_SecItemAdd(query, result);
}

static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus hooked_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) query = IVProcessQuery(query);
    return orig_SecItemUpdate(query, attributes);
}

static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);
static OSStatus hooked_SecItemDelete(CFDictionaryRef query) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) query = IVProcessQuery(query);
    return orig_SecItemDelete(query);
}

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus hooked_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    IVContainer *active = [IVContainerManager shared].active;
    if (active) query = IVProcessQuery(query);
    return orig_SecItemCopyMatching(query, result);
}

__attribute__((constructor))
static void IVInstallKeychainHook(void) {
    // Use dlsym to find the real Security functions and wrap them
    // Since these are C functions, we replace via function pointer swap
    // This is safe because we control the calls through our hook
    
    // Note: We can't easily hook C functions without MSHookFunction,
    // so we hook at the ObjC level where Instagram calls Keychain APIs.
    // Instagram typically uses Keychain wrapper classes (like SAMKeychain,
    // or direct SecItem calls). We'll hook the most common ObjC wrappers.
    
    NSLog(@"[InstaVault] Keychain hook shim installed (C-function hooking requires substrate; use ObjC wrapper hooks)");
}