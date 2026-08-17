//
//  FLEXSwiftBridge.h
//  FLEX
//
//  Created as the ObjC ↔ Swift bridge for the SwiftUI surfaces.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The smallest possible surface the SwiftUI screens need from the ObjC runtime
/// machinery (heap scanning, instance navigation, local URL mapping). Swift views
/// call these; everything else stays in Objective-C.
@interface FLEXSwiftBridge : NSObject

#pragma mark - Heap Objects

/// Scans the heap on a background queue, reporting determinate progress on the
/// main queue, then calls completion on the main queue with the results.
+ (void)beginHeapScanWithProgress:(void (^)(double progress))progress
                       completion:(void (^)(NSArray<NSString *> *names,
                                            NSDictionary<NSString *, NSNumber *> *counts,
                                            NSDictionary<NSString *, NSNumber *> *sizes))completion
    NS_SWIFT_NAME(beginHeapScan(withProgress:completion:));

/// Pushes the classic FLEX instance list for a class onto the host's navigation stack.
+ (void)pushInstancesOfClass:(NSString *)className
                        from:(UIViewController *)host
    NS_SWIFT_NAME(pushInstances(ofClass:from:));

#pragma mark - Map Local

/// Every mapping as @{ @"url": ..., @"file": ..., @"enabled": @YES/@NO } dictionaries.
+ (NSArray<NSDictionary<NSString *, id> *> *)localMappings;
+ (void)setLocalMappingForURL:(NSString *)url
                       toFile:(NSString *)path
    NS_SWIFT_NAME(setLocalMapping(forURL:toFile:));
+ (void)removeLocalMappingForURL:(NSString *)url
    NS_SWIFT_NAME(removeLocalMapping(forURL:));
+ (void)removeAllLocalMappings;
/// Enables or disables an existing mapping without removing it.
+ (void)setEnabled:(BOOL)enabled
 forLocalMappingURL:(NSString *)url
    NS_SWIFT_NAME(setEnabled(_:forLocalMappingURL:));
/// Full paths of files in the app's Documents directory.
+ (NSArray<NSString *> *)localFilesInDocuments;
/// Creates a new empty file with a unique name and returns its full path.
+ (nullable NSString *)createLocalFileWithBaseName:(NSString *)name
    NS_SWIFT_NAME(createLocalFile(withBaseName:));
/// Reads a file as UTF-8 text.
+ (nullable NSString *)fileContentsAtPath:(NSString *)path
    NS_SWIFT_NAME(fileContents(atPath:));
/// Writes UTF-8 text to a file, returning whether the write succeeded.
+ (BOOL)writeContents:(NSString *)contents
          toFileAtPath:(NSString *)path
    NS_SWIFT_NAME(writeContents(_:toFileAtPath:));
/// A sensible Content-Type for a file path.
+ (NSString *)mimeTypeForFile:(NSString *)path;

@end

NS_ASSUME_NONNULL_END