#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Redirection #2 — the keychain wall (plan-directeur §2, §5.2).
/// Rebinds SecItemAdd/CopyMatching/Update/Delete via fishhook and namespaces
/// every password keychain item by container — prefixing kSecAttrService for
/// generic-password items AND kSecAttrServer for internet-password items, on
/// BOTH writes and read queries, then stripping the prefix from returned
/// attributes. Namespacing internet-passwords too is what stops one container's
/// login from clobbering another's shared session material.
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

/// Delete every namespaced password item (generic- AND internet-password) whose
/// service/server begins with `prefix`. Pass "IV:<cid>:" to wipe one container's
/// credentials on removal, or "IV:" to wipe all containers' credentials on a
/// global reset. Un-prefixed real items (the default container's own login) are
/// never touched. Returns the number of items deleted. Safe to call from the
/// default container too (falls back to the real keychain functions).
+ (NSInteger)purgeItemsWithPrefix:(NSString *)prefix;

/// Count (without deleting) namespaced password items whose service/server begins
/// with `prefix`. Used after a purge to verify nothing survived: a non-zero result
/// means the wipe was only partial and the caller must report failure.
+ (NSInteger)countItemsWithPrefix:(NSString *)prefix;

@end

NS_ASSUME_NONNULL_END
