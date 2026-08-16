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

@end

NS_ASSUME_NONNULL_END
