#import <Foundation/Foundation.h>
extern "C" CFTypeRef MGCopyAnswer(CFStringRef q);
static CFTypeRef (*orig_MG)(CFStringRef);
static CFTypeRef hook_MG(CFStringRef q) {
    NSString *k=(__bridge NSString *)q;
    IVDeviceSpoofing *s=[IVDeviceSpoofing shared];
    if(s.on){
        if([k isEqualToString:@"UniqueDeviceID"]&&s.udid)return(__bridge_retained CFTypeRef)[s.udid copy];
        if([k isEqualToString:@"SerialNumber"]&&s.serial)return(__bridge_retained CFTypeRef)[s.serial copy];
        if([k isEqualToString:@"WiFiAddress"]&&s.wifi)return(__bridge_retained CFTypeRef)[s.wifi copy];
        if([k isEqualToString:@"BluetoothAddress"]&&s.bt)return(__bridge_retained CFTypeRef)[s.bt copy];
        if([k isEqualToString:@"ProductType"]&&s.model)return(__bridge_retained CFTypeRef)[s.model copy];
        if([k isEqualToString:@"UserAssignedDeviceName"]&&s.name)return(__bridge_retained CFTypeRef)[s.name copy];
        if([k isEqualToString:@"ProductVersion"]&&s.os)return(__bridge_retained CFTypeRef)[s.os copy];
    }
    return orig_MG(q);
}
%ctor { MSHookFunction((void*)MGCopyAnswer,(void*)hook_MG,(void**)&orig_MG); NSLog(@"[InstaVault] HW hook"); }
