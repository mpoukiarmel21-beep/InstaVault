#import <Foundation/Foundation.h>
#import <AdSupport/AdSupport.h>
#import "IVContainer.h"
#import "IVContainerManager.h"
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    IVContainer *a=[IVContainerManager shared].active;
    if(a&&a.device)return [[NSUUID alloc] initWithUUIDString:a.device.idfa];
    return %orig;
}
- (BOOL)isAdvertisingTrackingEnabled { return YES; }
%end
