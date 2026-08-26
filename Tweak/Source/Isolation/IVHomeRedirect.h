#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Redirection #1 of the two-global-redirects model (plan-directeur §2, §5.1).
/// Points CFFIXED_USER_HOME + HOME (+ TMPDIR) at the active container's root so
/// Foundation derives NSHomeDirectory / Documents / Library / Caches / tmp /
/// NSUserDefaults / cookies from it — one redirect isolates ALL file storage.
///
/// The default container is NOT redirected (existing logins survive).
@interface IVHomeRedirect : NSObject

/// Apply the HOME redirect for a container. No-op (returns YES) for the default
/// container. Pre-creates the skeleton dirs first. MUST run before any Instagram
/// code touches a path (i.e. from the single constructor, right after the store
/// load).
///
/// Returns YES if the redirect is in effect (or intentionally skipped for the
/// default container), NO if the skeleton could not be built. On NO the caller
/// MUST NOT install the keychain hook — a namespaced keychain over a real-sandbox
/// filesystem is a split-brain leak (files land in the shared sandbox while
/// credentials are prefixed, or vice-versa).
+ (BOOL)applyForContainer:(IVContainer *)container;

/// Undo a previously-applied redirect, pointing HOME/CFFIXED_USER_HOME/TMPDIR
/// back at the real sandbox. Used to keep the two redirects atomic: if the
/// keychain hook fails to install after HOME was redirected, we revert HOME so
/// the launch runs consistently on the real sandbox instead of half-isolated.
+ (void)revertToRealHome;

@end

NS_ASSUME_NONNULL_END
