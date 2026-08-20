#import <Foundation/Foundation.h>
@class IVContainer;
extern NSString *const kIVListChanged;
extern NSString *const kIVActiveChanged;

@interface IVContainerManager : NSObject
@property (nonatomic, strong, readonly) NSMutableArray<IVContainer *> *list;
@property (nonatomic, strong, readonly) IVContainer *active;
+ (instancetype)shared;
- (IVContainer *)create:(NSString *)name;
- (BOOL)remove:(IVContainer *)c;
- (BOOL)activate:(IVContainer *)c;
- (BOOL)save;
- (BOOL)load;
@end
