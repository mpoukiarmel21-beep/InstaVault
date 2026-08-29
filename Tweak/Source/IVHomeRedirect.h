#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// Redirection — points CFFIXED_USER_HOME + HOME (+ TMPDIR) at the active
/// container's root so Foundation derives NSHomeDirectory / Documents / Library /
/// Caches / tmp / NSUserDefaults / cookies from it — one redirect isolates ALL
/// file storage for an active container.
///
/// Only called when a container is ACTIVE (a nil active container = the real
/// Instagram account, which stays on the real sandbox).
@interface IVHomeRedirect : NSObject

+ (BOOL)applyForContainer:(IVContainer *)container;
+ (void)revertToRealHome;

@end

NS_ASSUME_NONNULL_END
