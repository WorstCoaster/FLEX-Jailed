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

/// Presents a searchable list of every live object on the heap, grouped by
/// class, plus the well-known singletons (app, windows, defaults, etc.).
/// Used when an argument is typed as plain `id` and has no class hint.
+ (instancetype)pickerForAnyObjectWithCompletion:(void(^)(id object))completion;

/// The class name encoded in an Objective-C type encoding, or nil.
/// Handles the `@"ClassName"` form and returns nil for plain `@` (id) or `#` (Class).
+ (nullable NSString *)classNameFromTypeEncoding:(const char *)typeEncoding;

/// Whether live instances can be picked for the given type encoding.
/// Plain object types (`@`) pick from the whole heap; `#` (Class) is not
/// enumerated because class objects are not guaranteed to be heap allocations.
+ (BOOL)canPickInstancesOfTypeEncoding:(const char *)typeEncoding;

@end

NS_ASSUME_NONNULL_END
