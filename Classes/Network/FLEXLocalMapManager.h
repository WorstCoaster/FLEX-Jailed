//
//  FLEXLocalMapManager.h
//  FLEX
//
//  Created for the "Map Local" network feature.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Persists "Map Local" rules: remote URL → local file in the app sandbox.
/// When a rule matches, FLEXLocalMappingURLProtocol serves the local file
/// instead of hitting the network, like Charles/Proxyman's "Map Local".
@interface FLEXLocalMapManager : NSObject

+ (instancetype)sharedManager;

/// Every mapping as @{ @"url": ..., @"file": ... } dictionaries.
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *allMappings;

/// The local file path serving \c url, or nil if there is no mapping.
- (nullable NSString *)localFilePathForURL:(NSURL *)url;

/// Whether a mapping exists for the given URL.
- (BOOL)hasMappingForURL:(NSURL *)url;

/// Adds or replaces a mapping for the given URL string.
- (void)setMappingForURLString:(NSString *)urlString toFilePath:(NSString *)filePath;

/// Removes the mapping for the given URL string, if any.
- (void)removeMappingForURLString:(NSString *)urlString;

/// Removes every mapping.
- (void)removeAllMappings;

/// Full paths of files inside the app's Documents directory, for the picker UI.
- (NSArray<NSString *> *)localFilesInDocuments;

/// A reasonable Content-Type for a file path based on its extension.
- (NSString *)mimeTypeForFile:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
