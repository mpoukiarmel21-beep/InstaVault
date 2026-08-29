#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// CFPreferences redirect. On iOS 26 the preferences daemon (cfprefsd) resolves a
/// domain's plist path over XPC from the PROCESS sandbox, ignoring
/// CFFIXED_USER_HOME — so the HOME redirect does NOT isolate NSUserDefaults /
/// CFPreferences. Instagram stores per-install identity there (device_id,
/// phone_id, cached session hints), so without this hook every container shares
/// one defaults store.
///
/// Fix (LiveContainer technique): swizzle the private
/// -[CFPrefsPlistSource initWithDomain:user:byHost:containerPath:containingPreferences:]
/// so every non-Apple domain's plist PATH is rewritten into the active container's
/// Library/Preferences, keeping the real appID. com.apple.* domains pass through.
@interface IVPrefsHook : NSObject

+ (BOOL)installForContainer:(IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
