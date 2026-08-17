//
//  FLEXLocalMappingURLProtocol.h
//  FLEX
//
//  Created for the "Map Local" network feature.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// An NSURLProtocol that serves local files in place of matched remote URLs.
/// It is registered once when the dylib loads; canInitWithRequest: only returns
/// YES for URLs with an active local mapping, so it is inert otherwise.
@interface FLEXLocalMappingURLProtocol : NSURLProtocol

@end

NS_ASSUME_NONNULL_END