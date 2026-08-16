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

/// Every selector name reachable on the given object (instance methods) or
/// class (class methods), including inherited ones, sorted alphabetically.
/// Useful for populating the suggested-values pool for `SEL` arguments.
+ (NSArray<NSString *> *)selectorNamesForObject:(id)object
                                 instanceMethod:(BOOL)instanceMethod;

@end
