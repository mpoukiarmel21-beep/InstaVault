#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Redirection #2 — the keychain wall (plan-directeur §2, §5.2).
/// Rebinds SecItemAdd/CopyMatching/Update/Delete via fishhook and namespaces
/// every keychain item by container, prefixing kSecAttrService on BOTH writes
/// AND read queries, then stripping the prefix from returned attributes.
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

@end

NS_ASSUME_NONNULL_END
