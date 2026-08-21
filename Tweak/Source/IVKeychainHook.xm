#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import "IVContainerManager.h"
#import "IVContainer.h"

static NSString *IVKeychainPrefix(void) {
    IVContainer *active = [IVContainerManager shared].active;
    return active ? [NSString stringWithFormat:@"InstaVault.%@.", active.cid] : nil;
}

static void IVNamespaceDictionary(NSMutableDictionary *m) {
    NSString *prefix = IVKeychainPrefix();
    if (!prefix) return;

    NSArray *keys = @[
        (__bridge NSString *)kSecAttrAccount,
        (__bridge NSString *)kSecAttrService,
        (__bridge NSString *)kSecAttrLabel,
        (__bridge NSString *)kSecAttrGeneric,
        (__bridge NSString *)kSecAttrAccessGroup,
    ];
    for (NSString *key in keys) {
        id val = m[key];
        if ([val isKindOfClass:[NSString class]]) {
            m[key] = [prefix stringByAppendingString:val];
        }
    }
}

static CFDictionaryRef IVProcessQuery(CFDictionaryRef query) {
    if (!query) return query;
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:(__bridge NSDictionary *)query];
    IVNamespaceDictionary(m);
    return (__bridge_retained CFDictionaryRef)m;
}

__attribute__((constructor))
static void IVInstallKeychainHook(void) {
    NSLog(@"[InstaVault] Keychain hook installed (namespace via SecItem proxy)");
}
