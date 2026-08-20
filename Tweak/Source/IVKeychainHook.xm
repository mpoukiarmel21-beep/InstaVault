#import <Foundation/Foundation.h>

__attribute__((constructor))
static void initKeychainHook() {
    NSLog(@"[InstaVault] Keychain hook disabled for stability");
}
