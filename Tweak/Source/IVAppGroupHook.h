#import <Foundation/Foundation.h>
#import "IVContainer.h"

NS_ASSUME_NONNULL_BEGIN

/// App Group container isolation.
///
/// Instagram is built on Meta's FBSDK stack, which persists part of its session /
/// identity state in the SHARED APP GROUP container
/// (`-[NSFileManager containerURLForSecurityApplicationGroupIdentifier:]`), NOT in
/// the app sandbox that the HOME redirect covers. Two problems follow for a
/// multi-container tweak on a sideloaded build:
///
///   1. Cross-container leak: every container resolves the SAME app-group
///      container URL, so one container's FBSDK session material bleeds into
///      another.
///
///   2. Sideload crash: after a personal-cert re-sign the App Group entitlement
///      is remapped/stripped, so the real call can return nil and FBSDK code
///      that force-unwraps the container URL crashes post-login.
///
/// This hook swizzles the (public) NSFileManager selector and, for a non-nil
/// active container, returns a container-local path
/// `<containerRoot>/AppGroups/<group>` (skeleton pre-created), giving each
/// container its own private app-group store. Substrate-free:
/// `method_setImplementation`, same technique as IVPrefsHook.
@interface IVAppGroupHook : NSObject

+ (BOOL)installForContainer:(IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
