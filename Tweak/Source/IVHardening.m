#import "IVHardening.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - Shared failure

// DeviceCheck's own error space. Returning DCErrorFeatureUnsupported (== 1) in
// DCErrorDomain is exactly what a real device without the feature produces, so a
// caller that inspects the error sees nothing anomalous.
static NSError *IVUnsupportedError(void) {
    return [NSError errorWithDomain:@"com.apple.devicecheck.error"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey:
                                           @"The operation couldn't be completed. (Feature unsupported.)" }];
}

#pragma mark - Swizzle helpers

// Replace an instance method that returns BOOL with a constant.
static void IVSetBOOLReturn(Class cls, SEL sel, BOOL value) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^BOOL(id _self) { return value; });
    method_setImplementation(m, imp);
}

// Replace `- (void)fooWithCompletionHandler:(void(^)(id result, NSError *error))completion`
// so it always fails asynchronously with the unsupported error. Object result
// types (NSData*, NSString*) share one ABI, so a single (id, NSError*) block
// covers generateToken… (NSData) and generateKey… (NSString) alike.
static void IVFailCompletion(Class cls, SEL sel) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^void(id _self, void (^completion)(id, NSError *)) {
        if (!completion) return;
        NSError *err = IVUnsupportedError();
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ completion(nil, err); });
    });
    method_setImplementation(m, imp);
}

// Same, for the two-leading-argument App Attest methods:
//   - attestKey:clientDataHash:completionHandler:
//   - generateAssertion:clientDataHash:completionHandler:
// Both prefix args are object pointers (NSString*/NSData*), so (id, id) works.
static void IVFailCompletion2(Class cls, SEL sel) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP imp = imp_implementationWithBlock(^void(id _self, id a1, id a2, void (^completion)(id, NSError *)) {
        if (!completion) return;
        NSError *err = IVUnsupportedError();
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ completion(nil, err); });
    });
    method_setImplementation(m, imp);
}

#pragma mark - AutoFill / QuickType suppression

// The textContentTypes whose AutoFill strip pulls from the shared
// Keychain/contacts store and would re-surface another container's identity into
// a fresh signup field. oneTimeCode is intentionally absent: SMS OTP autofill
// must keep working so account creation isn't broken.
static IMP gOrigTextContentTypeIMP = NULL;

static UITextContentType _Nullable iv_textContentType(id self, SEL _cmd) {
    UITextContentType orig = gOrigTextContentTypeIMP
        ? ((UITextContentType (*)(id, SEL))gOrigTextContentTypeIMP)(self, _cmd)
        : nil;
    if ([orig isEqualToString:UITextContentTypeEmailAddress] ||
        [orig isEqualToString:UITextContentTypeUsername] ||
        [orig isEqualToString:UITextContentTypePassword] ||
        [orig isEqualToString:UITextContentTypeNewPassword]) {
        return nil;
    }
    return orig;
}

static void IVSuppressCredentialAutoFill(void) {
    Method m = class_getInstanceMethod([UITextField class], @selector(textContentType));
    if (!m) return;
    IMP prev = method_setImplementation(m, (IMP)iv_textContentType);
    if (!gOrigTextContentTypeIMP) gOrigTextContentTypeIMP = prev;  // never capture our own thunk
}

#pragma mark - Install

@implementation IVHardening

+ (void)installForContainer:(IVContainer *)container {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 1) DeviceCheck — one device-global token per app across all containers.
        Class dc = NSClassFromString(@"DCDevice");
        IVSetBOOLReturn(dc, @selector(isSupported), NO);
        IVFailCompletion(dc, @selector(generateTokenWithCompletionHandler:));

        // 2) App Attest — one hardware-backed key per app across all containers.
        Class aa = NSClassFromString(@"DCAppAttestService");
        IVSetBOOLReturn(aa, @selector(isSupported), NO);
        IVFailCompletion(aa, @selector(generateKeyWithCompletionHandler:));
        IVFailCompletion2(aa, @selector(attestKey:clientDataHash:completionHandler:));
        IVFailCompletion2(aa, @selector(generateAssertion:clientDataHash:completionHandler:));

        // 3) AutoFill/QuickType credential strip — the cross-container email leak.
        IVSuppressCredentialAutoFill();
    });
}

@end
