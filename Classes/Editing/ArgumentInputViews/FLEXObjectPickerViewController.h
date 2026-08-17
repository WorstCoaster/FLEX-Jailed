//
//  FLEXObjectPickerViewController.h
//  FLEX
//
//  Created for the instance-picker argument input.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presents a pickable list of instances relevant to the requested class:
/// well-known singletons plus objects reachable from the host app's current UI.
/// FLEX's own window and UI are excluded, so the list only shows objects the
/// user is actually debugging. When the UI graph has no matches, the picker
/// shows an empty state with an on-demand, bounded heap scan — heap objects are
/// surfaced without being retained or messaged to avoid crashes.
/// Selecting a row invokes the completion block and pops the picker.
@interface FLEXObjectPickerViewController : UITableViewController

+ (instancetype)pickerForClassName:(NSString *)className
                        completion:(void(^)(id object))completion;

/// Presents a searchable list of objects reachable from the host app's current
/// UI, grouped by class, plus the well-known singletons (app, windows, defaults,
/// etc.). Used when an argument is typed as plain `id` and has no class hint.
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
