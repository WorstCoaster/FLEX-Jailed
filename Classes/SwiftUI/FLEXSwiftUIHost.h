//
//  FLEXSwiftUIHost.h
//  FLEX
//
//  Created as the ObjC-facing declaration of the SwiftUI host. The concrete
//  implementation lives in FLEXSwiftUI.swift (class FLEXSwiftUIHost).
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FLEXSwiftUIHost : NSObject

/// A SwiftUI "Heap Objects" screen (class counts + sizes) with a determinate
/// progress bar while the heap is scanned on a background queue.
+ (UIViewController *)heapObjectsController;

/// A SwiftUI "Map Local" editor. Optionally pre-fills the URL from the selected
/// network transaction; completion is called whenever a mapping changes.
+ (UIViewController *)localMapControllerWithPrefilledURL:(nullable NSString *)url
                                             completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END