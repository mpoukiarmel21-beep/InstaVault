#import "IVCameraHook.h"
#import "IVPaths.h"
#import "IVDiagnostics.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================================
// IVVideoFeeder — decodes the chosen video and, on demand, produces one frame as
// a CVPixelBuffer scaled/cropped (aspect-fill) to a requested geometry + pixel
// format so it drops straight into the capture stream. Loops seamlessly by
// recreating the reader when the track ends. Thread-safe.
// ============================================================================
@interface IVVideoFeeder : NSObject
- (instancetype)initWithVideoURL:(NSURL *)url;
- (CVPixelBufferRef)copyPixelBufferForWidth:(size_t)width
                                     height:(size_t)height
                                pixelFormat:(OSType)pixelFormat CF_RETURNS_RETAINED;
@end

static CGImagePropertyOrientation IVOrientationForTransform(CGAffineTransform t) {
    CGFloat deg = atan2(t.b, t.a) * 180.0 / M_PI;
    if (deg < 0) deg += 360.0;
    if (fabs(deg -  90.0) < 1.0) return kCGImagePropertyOrientationRight;
    if (fabs(deg - 270.0) < 1.0) return kCGImagePropertyOrientationLeft;
    if (fabs(deg - 180.0) < 1.0) return kCGImagePropertyOrientationDown;
    return kCGImagePropertyOrientationUp;
}


@implementation IVVideoFeeder {
    NSURL *_url;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    CIContext *_ci;
    CVPixelBufferPoolRef _pool;
    size_t _poolW, _poolH;
    OSType _poolFmt;
    NSLock *_lock;
    CGImagePropertyOrientation _orient;
}

- (instancetype)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url;
        _lock = [NSLock new];
        _orient = kCGImagePropertyOrientationUp;
        _ci = [CIContext contextWithOptions:@{ kCIContextWorkingColorSpace: [NSNull null] }];
    }
    return self;
}

- (void)dealloc {
    if (_pool) CVPixelBufferPoolRelease(_pool);
}

- (BOOL)_startReaderLocked {
    if (_reader) { [_reader cancelReading]; _reader = nil; _output = nil; }
    NSError *err = nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:_url options:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) { IVErr(@"camera feeder: no video track in %@", _url.lastPathComponent); return NO; }
    _orient = IVOrientationForTransform(track.preferredTransform);
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&err];
    if (!reader) { IVErr(@"camera feeder: reader init failed: %@", err); return NO; }
    NSDictionary *settings = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
    AVAssetReaderTrackOutput *out =
        [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
    out.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:out]) { IVErr(@"camera feeder: cannot add output"); return NO; }
    [reader addOutput:out];
    if (![reader startReading]) { IVErr(@"camera feeder: startReading failed: %@", reader.error); return NO; }
    _reader = reader; _output = out;
    return YES;
}

- (CVPixelBufferRef)_copyNextSourcePixelBufferLocked CF_RETURNS_RETAINED {
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!_reader && ![self _startReaderLocked]) return NULL;
        CMSampleBufferRef sb = [_output copyNextSampleBuffer];
        if (sb) {
            CVImageBufferRef img = CMSampleBufferGetImageBuffer(sb);
            CVPixelBufferRef px = img ? (CVPixelBufferRef)CVBufferRetain(img) : NULL;
            CFRelease(sb);
            if (px) return px;
        }
        if (_reader) { [_reader cancelReading]; _reader = nil; _output = nil; }
    }
    return NULL;
}

- (BOOL)_ensurePoolLockedW:(size_t)w h:(size_t)h fmt:(OSType)fmt {
    if (_pool && _poolW == w && _poolH == h && _poolFmt == fmt) return YES;
    if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
    NSDictionary *attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(fmt),
        (id)kCVPixelBufferWidthKey: @(w),
        (id)kCVPixelBufferHeightKey: @(h),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVReturn r = CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL,
                                         (__bridge CFDictionaryRef)attrs, &_pool);
    if (r != kCVReturnSuccess) { IVErr(@"camera feeder: pool create failed (%d)", (int)r); _pool = NULL; return NO; }
    _poolW = w; _poolH = h; _poolFmt = fmt;
    return YES;
}

- (CVPixelBufferRef)copyPixelBufferForWidth:(size_t)width
                                     height:(size_t)height
                                pixelFormat:(OSType)pixelFormat CF_RETURNS_RETAINED {
    if (width == 0 || height == 0) return NULL;
    [_lock lock];
    CVPixelBufferRef out = NULL;
    @try {
        CVPixelBufferRef src = [self _copyNextSourcePixelBufferLocked];
        if (!src) return NULL;
        if (![self _ensurePoolLockedW:width h:height fmt:pixelFormat]) { CFRelease(src); return NULL; }

        CVReturn r = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &out);
        if (r != kCVReturnSuccess || !out) { CFRelease(src); return NULL; }

        CIImage *ciSrc = [CIImage imageWithCVPixelBuffer:src];
        if (_orient != kCGImagePropertyOrientationUp) {
            ciSrc = [ciSrc imageByApplyingCGOrientation:_orient];
            CGRect e = ciSrc.extent;
            if (e.origin.x != 0 || e.origin.y != 0) {
                ciSrc = [ciSrc imageByApplyingTransform:CGAffineTransformMakeTranslation(-e.origin.x, -e.origin.y)];
            }
        }
        CGSize s = ciSrc.extent.size;
        if (s.width > 0 && s.height > 0) {
            CGFloat scale = MAX((CGFloat)width / s.width, (CGFloat)height / s.height);
            CGFloat sw = s.width * scale, sh = s.height * scale;
            CGFloat tx = ((CGFloat)width - sw) * 0.5, ty = ((CGFloat)height - sh) * 0.5;
            CIImage *shown = [ciSrc imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
            shown = [shown imageByApplyingTransform:CGAffineTransformMakeTranslation(tx, ty)];
            [_ci render:shown toCVPixelBuffer:out];
        } else {
            [_ci render:ciSrc toCVPixelBuffer:out];
        }
        CFRelease(src);
    } @catch (__unused NSException *e) {
        if (out) { CFRelease(out); out = NULL; }
    } @finally {
        [_lock unlock];
    }
    return out;
}
@end

// ============================================================================
// Frame replacement in the app's own AVCaptureVideoDataOutput delegate callback.
// ============================================================================

static IVVideoFeeder *gFeeder = nil;
static NSURL *gVideoURL = nil;
static SEL gDidOutputSel;
static NSMutableSet<NSNumber *> *gSwizzledDelegates;

static CMSampleBufferRef IVCreateSampleBuffer(CMSampleBufferRef original,
                                              CVPixelBufferRef pixels) CF_RETURNS_RETAINED {
    if (!original || !pixels) return NULL;
    CMSampleTimingInfo timing = kCMTimingInfoInvalid;
    CMSampleBufferGetSampleTimingInfo(original, 0, &timing);

    CMVideoFormatDescriptionRef fmt = NULL;
    OSStatus s = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixels, &fmt);
    if (s != noErr || !fmt) return NULL;

    CMSampleBufferRef out = NULL;
    s = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixels, fmt, &timing, &out);
    CFRelease(fmt);
    if (s != noErr) { if (out) CFRelease(out); return NULL; }
    return out;
}

static void IVSwizzleDelegateClass(Class cls) {
    if (!cls) return;
    @synchronized (gSwizzledDelegates) {
        NSNumber *key = @((uintptr_t)cls);
        if ([gSwizzledDelegates containsObject:key]) return;
        [gSwizzledDelegates addObject:key];
    }
    Method m = class_getInstanceMethod(cls, gDidOutputSel);
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    IMP origIMP = method_getImplementation(m);

    IMP newIMP = imp_implementationWithBlock(^(id delegateSelf,
                                               AVCaptureOutput *output,
                                               CMSampleBufferRef sampleBuffer,
                                               AVCaptureConnection *conn) {
        CMSampleBufferRef replacement = NULL;
        @try {
            IVVideoFeeder *feeder = gFeeder;
            CVImageBufferRef img = sampleBuffer ? CMSampleBufferGetImageBuffer(sampleBuffer) : NULL;
            if (feeder && img) {
                size_t w = CVPixelBufferGetWidth(img);
                size_t h = CVPixelBufferGetHeight(img);
                OSType fmt = CVPixelBufferGetPixelFormatType(img);
                CVPixelBufferRef newPix = [feeder copyPixelBufferForWidth:w height:h pixelFormat:fmt];
                if (newPix) {
                    replacement = IVCreateSampleBuffer(sampleBuffer, newPix);
                    CFRelease(newPix);
                }
            }
        } @catch (__unused NSException *e) {
            if (replacement) { CFRelease(replacement); replacement = NULL; }
        }
        CMSampleBufferRef deliver = replacement ?: sampleBuffer;
        ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))origIMP)(
            delegateSelf, gDidOutputSel, output, deliver, conn);
        if (replacement) CFRelease(replacement);
    });
    class_replaceMethod(cls, gDidOutputSel, newIMP, types);
    IVLog(@"camera: hooked delegate %s", class_getName(cls));
}

static void IVInstallDelegateLearner(void) {
    Class outCls = objc_getClass("AVCaptureVideoDataOutput");
    if (!outCls) { IVErr(@"camera: AVCaptureVideoDataOutput unavailable"); return; }
    SEL sel = @selector(setSampleBufferDelegate:queue:);
    Method m = class_getInstanceMethod(outCls, sel);
    if (!m) { IVErr(@"camera: setSampleBufferDelegate:queue: not found"); return; }
    const char *types = method_getTypeEncoding(m);
    IMP origIMP = method_getImplementation(m);

    IMP newIMP = imp_implementationWithBlock(^(id outputSelf,
                                               id<NSObject> delegate,
                                               dispatch_queue_t queue) {
        @try {
            if (delegate) IVSwizzleDelegateClass(object_getClass(delegate));
        } @catch (__unused NSException *e) {}
        ((void(*)(id, SEL, id, dispatch_queue_t))origIMP)(outputSelf, sel, delegate, queue);
    });
    class_replaceMethod(outCls, sel, newIMP, types);
    IVLog(@"camera: delegate learner installed");
}

// ============================================================================
// Preview overlay — put the video ON SCREEN over the live preview so the user
// SEES the virtual camera, not the real one.
// ============================================================================

static const void *kIVOverlayLayerKey  = &kIVOverlayLayerKey;
static const void *kIVOverlayPlayerKey = &kIVOverlayPlayerKey;
static const void *kIVOverlayLooperKey = &kIVOverlayLooperKey;

static void IVAttachOverlayToPreview(CALayer *preview) {
    if (!preview || !gVideoURL) return;
    if (objc_getAssociatedObject(preview, kIVOverlayLayerKey)) return;
    @try {
        AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
        player.muted = YES;
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:gVideoURL];
        AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
        AVPlayerLayer *pl = [AVPlayerLayer playerLayerWithPlayer:player];
        pl.videoGravity = AVLayerVideoGravityResizeAspectFill;
        pl.frame = preview.bounds;
        [preview addSublayer:pl];
        [player play];
        objc_setAssociatedObject(preview, kIVOverlayLayerKey,  pl,     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(preview, kIVOverlayPlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(preview, kIVOverlayLooperKey, looper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        IVLog(@"camera: preview overlay attached");
    } @catch (__unused NSException *e) {}
}

static void IVInstallPreviewOverlay(void) {
    Class prevCls = objc_getClass("AVCaptureVideoPreviewLayer");
    if (!prevCls) { IVErr(@"camera: AVCaptureVideoPreviewLayer unavailable"); return; }

    SEL setSessionSel = @selector(setSession:);
    Method sm = class_getInstanceMethod(prevCls, setSessionSel);
    if (sm) {
        const char *types = method_getTypeEncoding(sm);
        IMP origIMP = method_getImplementation(sm);
        IMP newIMP = imp_implementationWithBlock(^(id layerSelf, AVCaptureSession *session) {
            ((void(*)(id, SEL, AVCaptureSession *))origIMP)(layerSelf, setSessionSel, session);
            @try { if (session) IVAttachOverlayToPreview((CALayer *)layerSelf); }
            @catch (__unused NSException *e) {}
        });
        class_replaceMethod(prevCls, setSessionSel, newIMP, types);
    }

    SEL layoutSel = @selector(layoutSublayers);
    Method lm = class_getInstanceMethod(prevCls, layoutSel);
    if (lm) {
        const char *types = method_getTypeEncoding(lm);
        IMP origIMP = method_getImplementation(lm);
        IMP newIMP = imp_implementationWithBlock(^(id layerSelf) {
            ((void(*)(id, SEL))origIMP)(layerSelf, layoutSel);
            @try {
                CALayer *overlay = objc_getAssociatedObject(layerSelf, kIVOverlayLayerKey);
                if (overlay) overlay.frame = ((CALayer *)layerSelf).bounds;
            } @catch (__unused NSException *e) {}
        });
        class_replaceMethod(prevCls, layoutSel, newIMP, types);
    }
    IVLog(@"camera: preview overlay swizzles installed");
}

// ============================================================================
// Still-photo path — the actual verification CAPTURE.
// ============================================================================

static CIContext *gStillCtx = nil;
static NSMutableSet<NSNumber *> *gSwizzledPhotoDelegates;
static SEL gDidFinishPhotoSBSel;

static CGImageRef IVCopyStillFrameCGImage(size_t w, size_t h) CF_RETURNS_RETAINED {
    IVVideoFeeder *feeder = gFeeder;
    if (!feeder || w == 0 || h == 0) return NULL;
    CVPixelBufferRef px = [feeder copyPixelBufferForWidth:w height:h pixelFormat:kCVPixelFormatType_32BGRA];
    if (!px) return NULL;
    CGImageRef cg = NULL;
    @try {
        if (!gStillCtx) gStillCtx = [CIContext contextWithOptions:nil];
        CIImage *ci = [CIImage imageWithCVPixelBuffer:px];
        cg = [gStillCtx createCGImage:ci fromRect:ci.extent];
    } @catch (__unused NSException *e) { cg = NULL; }
    CVPixelBufferRelease(px);
    return cg;
}

static NSData *IVEncodeJPEGData(CGImageRef img, CGFloat quality) {
    if (!img) return nil;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dst =
        CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.jpeg"), 1, NULL);
    if (!dst) return nil;
    NSDictionary *props = @{ (__bridge id)kCGImageDestinationLossyCompressionQuality: @(quality) };
    CGImageDestinationAddImage(dst, img, (__bridge CFDictionaryRef)props);
    BOOL ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    return ok ? data : nil;
}

static void IVInstallPhotoAccessorHook(void) {
    Class cls = objc_getClass("AVCapturePhoto");
    if (!cls) { IVErr(@"camera: AVCapturePhoto unavailable — modern photo path not hooked"); return; }

    SEL fileSel = @selector(fileDataRepresentation);
    Method fm = class_getInstanceMethod(cls, fileSel);
    if (fm) {
        const char *types = method_getTypeEncoding(fm);
        IMP orig = method_getImplementation(fm);
        IMP repl = imp_implementationWithBlock(^NSData *(id photoSelf) {
            NSData *real = ((NSData *(*)(id, SEL))orig)(photoSelf, fileSel);
            if (!gFeeder || !gVideoURL) return real;
            @try {
                size_t W = 0, H = 0;
                CGImagePropertyOrientation orient = kCGImagePropertyOrientationUp;
                if (real.length) {
                    CGImageSourceRef s = CGImageSourceCreateWithData((__bridge CFDataRef)real, NULL);
                    if (s) {
                        NSDictionary *p = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(s, 0, NULL));
                        W = [p[(__bridge id)kCGImagePropertyPixelWidth] unsignedLongValue];
                        H = [p[(__bridge id)kCGImagePropertyPixelHeight] unsignedLongValue];
                        NSNumber *o = p[(__bridge id)kCGImagePropertyOrientation];
                        if (o) orient = (CGImagePropertyOrientation)o.intValue;
                        CFRelease(s);
                    }
                }
                BOOL swap = (orient == kCGImagePropertyOrientationLeft ||
                             orient == kCGImagePropertyOrientationRight ||
                             orient == kCGImagePropertyOrientationLeftMirrored ||
                             orient == kCGImagePropertyOrientationRightMirrored);
                size_t tW = swap ? H : W, tH = swap ? W : H;
                if (tW == 0 || tH == 0) { tW = 1080; tH = 1920; }
                if (tW > tH) { size_t t = tW; tW = tH; tH = t; }
                CGImageRef cg = IVCopyStillFrameCGImage(tW, tH);
                if (!cg) return real;
                NSData *out = IVEncodeJPEGData(cg, 0.92);
                CGImageRelease(cg);
                return out.length ? out : real;
            } @catch (__unused NSException *e) { return real; }
        });
        class_replaceMethod(cls, fileSel, repl, types);
    }

    SEL cgSel = @selector(CGImageRepresentation);
    Method cm = class_getInstanceMethod(cls, cgSel);
    if (cm) {
        const char *types = method_getTypeEncoding(cm);
        IMP orig = method_getImplementation(cm);
        IMP repl = imp_implementationWithBlock(^CGImageRef(id photoSelf) {
            CGImageRef real = ((CGImageRef(*)(id, SEL))orig)(photoSelf, cgSel);
            if (!gFeeder || !gVideoURL || !real) return real;
            @try {
                CGImageRef cg = IVCopyStillFrameCGImage(CGImageGetWidth(real), CGImageGetHeight(real));
                if (!cg) return real;
                return (CGImageRef)CFAutorelease(cg);
            } @catch (__unused NSException *e) { return real; }
        });
        class_replaceMethod(cls, cgSel, repl, types);
    }

    for (NSString *name in @[ @"pixelBuffer", @"previewPixelBuffer" ]) {
        SEL sel = NSSelectorFromString(name);
        Method pm = class_getInstanceMethod(cls, sel);
        if (!pm) continue;
        const char *types = method_getTypeEncoding(pm);
        IMP orig = method_getImplementation(pm);
        IMP repl = imp_implementationWithBlock(^CVPixelBufferRef(id photoSelf) {
            CVPixelBufferRef real = ((CVPixelBufferRef(*)(id, SEL))orig)(photoSelf, sel);
            if (!gFeeder || !gVideoURL || !real) return real;
            @try {
                size_t w = CVPixelBufferGetWidth(real), h = CVPixelBufferGetHeight(real);
                OSType fmt = CVPixelBufferGetPixelFormatType(real);
                CVPixelBufferRef px = [gFeeder copyPixelBufferForWidth:w height:h pixelFormat:fmt];
                if (!px) return real;
                return (CVPixelBufferRef)CFAutorelease(px);
            } @catch (__unused NSException *e) { return real; }
        });
        class_replaceMethod(cls, sel, repl, types);
    }

    IVLog(@"camera: still-photo accessors hooked (AVCapturePhoto)");
}

static void IVSwizzlePhotoDelegateClass(Class cls) {
    if (!cls) return;
    @synchronized (gSwizzledPhotoDelegates) {
        NSNumber *key = @((uintptr_t)cls);
        if ([gSwizzledPhotoDelegates containsObject:key]) return;
        [gSwizzledPhotoDelegates addObject:key];
    }
    Method m = class_getInstanceMethod(cls, gDidFinishPhotoSBSel);
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    IMP origIMP = method_getImplementation(m);

    IMP newIMP = imp_implementationWithBlock(^(id delegateSelf,
                                               AVCaptureOutput *output,
                                               CMSampleBufferRef photoSB,
                                               CMSampleBufferRef previewSB,
                                               id resolved, id bracket, NSError *error) {
        CMSampleBufferRef replacement = NULL;
        @try {
            IVVideoFeeder *feeder = gFeeder;
            CVImageBufferRef img = photoSB ? CMSampleBufferGetImageBuffer(photoSB) : NULL;
            if (feeder && img) {
                size_t w = CVPixelBufferGetWidth(img), h = CVPixelBufferGetHeight(img);
                OSType fmt = CVPixelBufferGetPixelFormatType(img);
                CVPixelBufferRef newPix = [feeder copyPixelBufferForWidth:w height:h pixelFormat:fmt];
                if (newPix) { replacement = IVCreateSampleBuffer(photoSB, newPix); CFRelease(newPix); }
            }
        } @catch (__unused NSException *e) {
            if (replacement) { CFRelease(replacement); replacement = NULL; }
        }
        CMSampleBufferRef deliver = replacement ?: photoSB;
        ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, CMSampleBufferRef, id, id, NSError *))origIMP)(
            delegateSelf, gDidFinishPhotoSBSel, output, deliver, previewSB, resolved, bracket, error);
        if (replacement) CFRelease(replacement);
    });
    class_replaceMethod(cls, gDidFinishPhotoSBSel, newIMP, types);
    IVLog(@"camera: hooked legacy photo delegate %s", class_getName(cls));
}

static void IVInstallPhotoDelegateLearner(void) {
    Class outCls = objc_getClass("AVCapturePhotoOutput");
    if (!outCls) return;
    SEL sel = @selector(capturePhotoWithSettings:delegate:);
    Method m = class_getInstanceMethod(outCls, sel);
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    IMP origIMP = method_getImplementation(m);

    IMP newIMP = imp_implementationWithBlock(^(id outputSelf, id settings, id<NSObject> delegate) {
        @try { if (delegate) IVSwizzlePhotoDelegateClass(object_getClass(delegate)); }
        @catch (__unused NSException *e) {}
        ((void(*)(id, SEL, id, id))origIMP)(outputSelf, sel, settings, delegate);
    });
    class_replaceMethod(outCls, sel, newIMP, types);
    IVLog(@"camera: photo delegate learner installed");
}


// ============================================================================
@implementation IVCameraHook

+ (void)installGlobal {
    NSString *path = [IVPaths globalCameraVideoPath];
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        IVLog(@"camera: no global verification video — real camera untouched");
        return;
    }
    gVideoURL = [NSURL fileURLWithPath:path];

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gDidOutputSel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        gDidFinishPhotoSBSel = @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:);
        gSwizzledDelegates = [NSMutableSet new];
        gSwizzledPhotoDelegates = [NSMutableSet new];
        IVInstallDelegateLearner();
        IVInstallPreviewOverlay();
        IVInstallPhotoAccessorHook();
        IVInstallPhotoDelegateLearner();
    });

    gFeeder = [[IVVideoFeeder alloc] initWithVideoURL:gVideoURL];
    IVLog(@"camera: global virtual camera armed (%@)", path.lastPathComponent);
}

@end
