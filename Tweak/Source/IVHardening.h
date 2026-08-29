#import <Foundation/Foundation.h>

@class IVContainer;

NS_ASSUME_NONNULL_BEGIN

/// In-process anti-correlation hardening for isolated containers.
///
/// The HOME / keychain / CFPreferences / App-Group redirects give each container
/// its own storage, but two device-global, Apple-signed identity oracles survive
/// every redirect and answer the SAME value on every container of one physical
/// device — the prime signal Badoo uses to correlate "many accounts, one phone"
/// and ban them all:
///   * DeviceCheck   (DCDevice)            — one per-device token, per app.
///   * App Attest     (DCAppAttestService) — one hardware-backed key, per app.
/// Both are neutralized here (report unsupported / fail), which is a legitimate,
/// non-anomalous state on real hardware (app extensions, SEP-less contexts).
///
/// It also suppresses the OS AutoFill / QuickType credential strip, which is what
/// re-surfaces a *previous* container's email or username into a NEW container's
/// signup field (the "la même adresse mail est réapparue" leak) — because that
/// strip is fed by the shared Keychain/contacts store, not by our per-container
/// files. SMS one-time-code AutoFill is deliberately preserved.
///
/// Process-global and container-independent, so it installs once (idempotent).
/// Gated to isolated containers only — never touches the real/default account.
@interface IVHardening : NSObject

/// Install the hardening. Idempotent; call once from Bootstrap under the
/// `isolated` gate. The container is accepted for API symmetry with the other
/// install methods; the neutralization is identical for every isolated container.
+ (void)installForContainer:(IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
