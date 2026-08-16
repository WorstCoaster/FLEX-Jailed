//
//  FLEXArgumentInputStringView.h
//  Flipboard
//
//  Created by Ryan Olson on 6/28/14.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXArgumentInputTextView.h"

@interface FLEXArgumentInputStringView : FLEXArgumentInputTextView

/// Whether the given ObjC type encoding is a selector (`:`, with an optional
/// const/qualifier prefix).
+ (BOOL)isSelectorTypeEncoding:(const char *)typeEncoding;

/// Whether the given ObjC type encoding is a plain `NSString` object
/// (not a selector or C-string).
+ (BOOL)isStringObjectTypeEncoding:(const char *)typeEncoding;

/// Every selector name reachable on the given object (instance methods) or
/// class (class methods), including inherited ones, sorted alphabetically.
/// Useful for populating the suggested-values pool for `SEL` arguments.
+ (NSArray<NSString *> *)selectorNamesForObject:(id)object
                                 instanceMethod:(BOOL)instanceMethod;

/// A fast, context-aware pool of likely string values for a method argument:
/// KVC key paths on the target (from the runtime) and the app's user-defaults
/// keys. Sorted and de-duplicated.
+ (NSArray<NSString *> *)suggestedStringsForObject:(id)object;

/// Asynchronously collects additional string candidates by scanning the heap
/// (live `NSString` instances) and the runtime (class and protocol names).
/// The completion block is always called on the main thread.
+ (void)additionalStringsWithCompletion:(void(^)(NSArray<NSString *> *values))completion;

@end
