#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// File-based ring logger. Writes to the REAL (un-redirected) home so logs are
/// shared across all containers and readable via the Files app:
///   <realHome>/Documents/InstaVault/logs/instavault.log
/// Golden rule (see plan-directeur §10): every disk write tests its return and
/// logs failure. No silent I/O.
@interface IVDiagnostics : NSObject

+ (instancetype)shared;

- (void)info:(NSString *)msg;
- (void)error:(NSString *)msg;
- (void)log:(NSString *)level msg:(NSString *)msg;

/// <realHome>/Documents/InstaVault/logs (created on demand).
- (NSString *)logDirectory;

@end

NS_ASSUME_NONNULL_END

#define IVLog(fmt, ...) [[IVDiagnostics shared] info:[NSString stringWithFormat:(fmt), ##__VA_ARGS__]]
#define IVErr(fmt, ...) [[IVDiagnostics shared] error:[NSString stringWithFormat:(fmt), ##__VA_ARGS__]]
