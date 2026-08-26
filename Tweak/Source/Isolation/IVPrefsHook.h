#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Redirection #3 of the isolation model (the missing third leg after HOME +
/// keychain). On iOS 26 the preferences daemon (cfprefsd) resolves a domain's
/// plist path over XPC from the PROCESS sandbox, ignoring CFFIXED_USER_HOME — so
/// the HOME redirect (redirection #1) does NOT isolate NSUserDefaults /
/// CFPreferences. Instagram stores per-install identity there (device_id,
/// phone_id, cached session hints), so without this hook every container shares
/// one defaults store and the app greets a returning container with the
/// "continue as …" account chooser instead of a live session.
///
/// The fix (LiveContainer technique): swizzle the private
/// -[CFPrefsPlistSource initWithDomain:user:byHost:containerPath:containingPreferences:]
/// so every non-Apple domain's plist PATH is rewritten into the active
/// container's Library/Preferences, keeping the real appID. com.apple.* domains
/// pass through untouched so system behaviour is preserved.
///
/// Fail-loud: if the private class/selector is absent (OS change), installForContainer:
/// returns NO and Bootstrap reverts to the real sandbox rather than launching
/// half-isolated. No-op / returns NO for the default container.
@interface IVPrefsHook : NSObject

+ (BOOL)installForContainer:(IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
