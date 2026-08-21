#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Security/Security.h>

__attribute__((constructor))
static void IVInstallKeychainHook(void) {
    NSLog(@"[InstaVault] Keychain hook installed");
}
