#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// One selectable row in an IVListPickerVC. `value` is the canonical token stored
/// (e.g. "iPhone17,1", "fr", "" for auto); `title` is what the user reads
/// (e.g. "iPhone 16 Pro", "Français"); `subtitle` is an optional secondary line
/// (e.g. the raw identifier or ISO code).
@interface IVListOption : NSObject
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
+ (instancetype)value:(NSString *)value title:(NSString *)title subtitle:(nullable NSString *)subtitle;
@end

/// A reusable single-choice picker pushed onto a navigation stack, styled for the
/// app's dark theme. Shows a checkmark on the currently-selected value; invokes
/// `onPick` then pops itself. Shared by the create screen (model, iOS version) and
/// the per-container settings sheet (language, region) so option lists live in one
/// place instead of being re-implemented per screen.
@interface IVListPickerVC : UITableViewController
- (instancetype)initWithTitle:(NSString *)title
                      options:(NSArray<IVListOption *> *)options
                selectedValue:(nullable NSString *)selectedValue
                       onPick:(void (^)(IVListOption *option))onPick;
@end

NS_ASSUME_NONNULL_END
