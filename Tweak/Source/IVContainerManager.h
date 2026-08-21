#import <Foundation/Foundation.h>
@class IVContainer;
@class IVDeviceSpoofing;
@class IVLocationSpoofing;
extern NSString *const kIVListChanged;
extern NSString *const kIVActiveChanged;

@interface IVContainerManager : NSObject {
    NSLock *_lock;
}
@property (nonatomic, strong, readonly) NSMutableArray<IVContainer *> *list;
@property (nonatomic, strong, readonly) IVContainer *active;
+ (instancetype)shared;
- (IVContainer *)create:(NSString *)name;
- (void)remove:(IVContainer *)c;
- (void)activate:(IVContainer *)c;
- (void)deactivate;
- (void)save;
- (void)load;
@end
