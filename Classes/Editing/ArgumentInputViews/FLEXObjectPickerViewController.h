//
//  FLEXObjectPickerViewController.h
//  FLEX
//
//  Created for the instance-picker argument input.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presents a pickable list of the live instances of a class (including
/// subclasses). Selecting a row invokes the completion block with the
/// retained instance and pops the picker.
@interface FLEXObjectPickerViewController : UITableViewController

+ (instancetype)pickerForClassName:(NSString *)className
                        completion:(void(^)(id object))completion;

/// The class name encoded in an Objective-C type encoding, or nil.
/// Handles the `@"ClassName"` form and returns nil for plain `@` (id) or `#` (Class).
+ (nullable NSString *)classNameFromTypeEncoding:(const char *)typeEncoding;

/// Whether live instances can be picked for the given type encoding.
+ (BOOL)canPickInstancesOfTypeEncoding:(const char *)typeEncoding;

@end

NS_ASSUME_NONNULL_END
