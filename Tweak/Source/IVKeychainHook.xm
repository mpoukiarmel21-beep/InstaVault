#import <Foundation/Foundation.h>
#import <Security/Security.h>
static NSMutableDictionary *modQ(NSDictionary *q) {
    IVContainer *a=[IVContainerManager shared].active;
    if(!a) return [q mutableCopy];
    NSMutableDictionary *m=[q mutableCopy];
    NSString *p=[NSString stringWithFormat:@"IV_%@_",a.cid];
    if(m[(__bridge id)kSecAttrService])m[(__bridge id)kSecAttrService]=[p stringByAppendingString:m[(__bridge id)kSecAttrService]];
    if(m[(__bridge id)kSecAttrAccount])m[(__bridge id)kSecAttrAccount]=[p stringByAppendingString:m[(__bridge id)kSecAttrAccount]];
    return m;
}
%hook SecItem
+ (OSStatus)SecItemAdd:(CFDictionaryRef)q results:(CFTypeRef *)r { return %orig((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q),r); }
+ (OSStatus)SecItemCopyMatching:(CFDictionaryRef)q result:(CFTypeRef *)r { return %orig((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q),r); }
+ (OSStatus)SecItemUpdate:(CFDictionaryRef)q withAttributes:(CFDictionaryRef)a { return %orig((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q),a); }
+ (OSStatus)SecItemDelete:(CFDictionaryRef)q { return %orig((__bridge CFDictionaryRef)modQ((__bridge NSDictionary *)q)); }
%end
