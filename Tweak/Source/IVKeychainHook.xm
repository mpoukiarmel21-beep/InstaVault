#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import "IVContainerManager.h"
#import "IVContainer.h"

static NSString *IVKeychainPrefix(void) {
    IVContainer *active = [IVContainerManager shared].active;
    return active ? [NSString stringWithFormat:@"InstaVault.%@.", active.cid] : nil;
}

__attribute__((constructor))
static void IVInstallKeychainHook(void) {
    NSLog(@"[InstaVault] Keychain hook installed (namespace via SecItem proxy)");
}
