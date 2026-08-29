#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Global virtual camera (shared by ALL containers).
///
/// When a global verification video is configured ([IVPaths globalCameraVideoPath]),
/// this feeds that video INTO Instagram's own native capture pipeline instead of the
/// real camera — for the passive photo / "Photo Verification" and profile-photo
/// capture. It works entirely in-process, substrate-free, and covers BOTH what
/// Instagram analyzes AND what the user sees on screen:
///
///   1. DATA PATH — swizzle `-[AVCaptureVideoDataOutput setSampleBufferDelegate:queue:]`
///      to learn the concrete delegate class the app installs the moment it wires up
///      the camera, then swizzle that delegate's
///      `-captureOutput:didOutputSampleBuffer:fromConnection:`. On every real camera
///      frame we replace the image buffer with the next frame decoded from the video
///      (scaled/cropped to the exact incoming geometry + pixel format, original timing
///      preserved) and forward THAT to the app. The video loops seamlessly.
///   2. PREVIEW PATH — swizzle `-[AVCaptureVideoPreviewLayer setSession:]` so the
///      instant the app shows a live preview we lay an AVPlayerLayer (looping the same
///      video, aspect-fill) OVER it. The overlay is kept sized to the preview via a
///      `layoutSublayers` swizzle.
///   3. STILL-PHOTO PATH — the actual verification CAPTURE. When the user taps the
///      shutter the app grabs a still via `AVCapturePhotoOutput` and reads the
///      resulting `AVCapturePhoto`'s data. The photo object is immutable, but every
///      consumer must call one of its data accessors to get pixels, so we swizzle
///      those class-wide — `-fileDataRepresentation`, `-CGImageRepresentation`,
///      `-pixelBuffer` and `-previewPixelBuffer` — to hand back the video frame. The
///      deprecated CMSampleBuffer photo callback is also covered via
///      `-[AVCapturePhotoOutput capturePhotoWithSettings:delegate:]`.
///
/// A single global video is shared by every container by design (the user swaps the
/// file to verify a different account). Defensive by design: any failure falls through
/// to the app's UNTOUCHED real frame / preview — never crashes or freezes the camera.
@interface IVCameraHook : NSObject

+ (void)installGlobal;

@end

NS_ASSUME_NONNULL_END
