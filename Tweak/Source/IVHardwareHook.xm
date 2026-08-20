#import <Foundation/Foundation.h>
#import "IVDeviceSpoofing.h"

__attribute__((constructor))
static void initHardwareHook() {
    NSLog(@"[InstaVault] HW hook disabled (MGCopyAnswer hook removed for stability)");
}
