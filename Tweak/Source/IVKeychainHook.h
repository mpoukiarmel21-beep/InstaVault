#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Redirection #2 — the keychain wall (plan-directeur §2, §5.2).
/// Rebinds SecItemAdd/CopyMatching/Update/Delete + SecKeyCreateRandomKey via
/// fishhook and namespaces every namespaceable keychain item by container —
/// prefixing kSecAttrService for generic-password items, kSecAttrServer for
/// internet-password items, AND kSecAttrApplicationTag (CFData) for kSecClassKey
/// items, on BOTH writes and read queries, then stripping the prefix from
/// returned attributes. Namespacing internet-passwords too is what stops one
/// container's login from clobbering another's shared session material;
/// namespacing the key tag is what stops the FBSDK/Meta device keypair from
/// being SHARED across containers and surviving container deletion — the
/// device-fingerprint leak behind the selfie / multi-account verification.
/// Modeled on iCTK/BlazeUniversal's "ADMIN:<bundle>_<cid>" scheme.
@interface IVKeychainHook : NSObject

/// Install the hooks with a per-container prefix (e.g. "IV:<cid>:").
/// Pass nil/empty (default container) to skip installation entirely, so the
/// default container reads/writes the real, un-prefixed keychain.
///
/// Returns YES if the hooks are in effect (or intentionally skipped for the
/// default container), NO if the fishhook rebind failed. On NO the caller must
/// treat isolation as failed and revert the HOME redirect (see
/// IVHomeRedirect revertToRealHome) so the launch stays on the real sandbox
/// rather than isolating files while leaking credentials to the shared keychain.
+ (BOOL)installWithPrefix:(nullable NSString *)prefix;

/// Install DEFAULT-container HIDE mode (P1). Binds the same hooks but keeps no
/// prefix: the default reads/writes the REAL keychain while EXCLUDING every
/// container's "IV:"-marked item from its reads, enumerations, and class-wide
/// deletes, so an account created inside a container never surfaces on the
/// default and a default class-delete can't sweep a container's device key. Also
/// applies the P2a accessibility upgrade so the real login survives a lock.
/// Mutually exclusive with installWithPrefix: — returns NO if a namespace prefix
/// is already active or the fishhook rebind fails.
+ (BOOL)installDefaultHideMode;

/// Delete every namespaced item — generic- AND internet-password (matched on
/// service/server) AND kSecClassKey (matched on its application-tag) — whose
/// namespace begins with `prefix`. Pass "IV:<cid>:" to wipe one container's
/// credentials AND device key on removal, or "IV:" to wipe all containers' on a
/// global reset. Un-prefixed real items (the default container's own login and
/// device key) are never touched. Returns the number of items deleted. Safe to
/// call from the default container too (falls back to the real keychain
/// functions).
+ (NSInteger)purgeItemsWithPrefix:(NSString *)prefix;

/// Delete the REAL (un-namespaced) login/session material — every generic- and
/// internet-password item whose service/server does NOT begin with "IV:" — to log
/// the PRINCIPAL / default account out on a global reset. The inverse of
/// purgeItemsWithPrefix:. The kSecClassKey device keypair is deliberately left
/// intact (a fingerprint, not a credential; wiping it would trigger a new-device
/// challenge on the real account). Returns the number of items deleted.
+ (NSInteger)purgeRealPasswordItems;

/// Count (without deleting) namespaced items (passwords + keys) whose namespace
/// begins with `prefix`. Used after a purge to verify nothing survived: a
/// non-zero result means the wipe was only partial and the caller must report
/// failure.
+ (NSInteger)countItemsWithPrefix:(NSString *)prefix;

@end

NS_ASSUME_NONNULL_END
