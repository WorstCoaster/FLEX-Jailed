//
//  FLEXStringPickerViewController.h
//  FLEX
//
//  Created for the selector/value suggestion pool.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A lightweight, searchable list of strings. Selecting a row invokes the
/// completion block with the chosen string and pops the picker.
@interface FLEXStringPickerViewController : UITableViewController

+ (instancetype)options:(NSArray<NSString *> *)options
                  title:(NSString *)title
             completion:(void(^)(NSString *value))completion;

/// Same as above, but lazily fetches more options via \c optionsProvider and
/// merges them into the list as they arrive. The provider receives a completion
/// block and calls it with the additional values.
+ (instancetype)options:(NSArray<NSString *> *)options
                  title:(NSString *)title
        optionsProvider:(nullable void(^)(void(^done)(NSArray<NSString *> *values)))optionsProvider
             completion:(void(^)(NSString *value))completion;

@end

NS_ASSUME_NONNULL_END
