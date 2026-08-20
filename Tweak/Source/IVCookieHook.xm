#import <Foundation/Foundation.h>
#import "IVContainer.h"
#import "IVContainerManager.h"
#import "IVFakeDevice.h"
%hook NSHTTPCookieStorage
+ (NSHTTPCookieStorage *)sharedHTTPCookieStorage {
    IVContainer *a=[IVContainerManager shared].active;
    if(!a)return %orig;
    static NSMutableDictionary *st; static dispatch_once_t o;
    dispatch_once(&o, ^{st=[NSMutableDictionary new];});
    NSHTTPCookieStorage *s=st[a.cid]; if(!s){s=%orig;st[a.cid]=s;} return s;
}
%end
%hook UIDevice
- (NSUUID *)identifierForVendor {
    IVContainer *a=[IVContainerManager shared].active;
    if(a&&a.device)return [[NSUUID alloc] initWithUUIDString:a.device.idfv];
    return %orig;
}
%end
