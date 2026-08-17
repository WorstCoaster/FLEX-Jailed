//
//  FLEXLocalMapManager.m
//  FLEX
//
//  Created for the "Map Local" network feature.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import "FLEXLocalMapManager.h"

/// Private helper declared up front so the call sites below compile cleanly.
@interface NSMutableArray (FLEXLocalMapManager)
- (void)removeObjectURL:(NSString *)key;
@end

static NSString * const kFLEXLocalMapMappingsDefaultsKey = @"FLEXLocalMapMappings";

@implementation FLEXLocalMapManager

+ (instancetype)sharedManager {
    static FLEXLocalMapManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [FLEXLocalMapManager new];
    });
    return shared;
}

#pragma mark - Persistence

- (NSMutableArray<NSDictionary<NSString *, id> *> *)mutableMappings {
    NSArray<NSDictionary<NSString *, id> *> *stored =
        [NSUserDefaults.standardUserDefaults arrayForKey:kFLEXLocalMapMappingsDefaultsKey];
    if (![stored isKindOfClass:[NSArray class]]) {
        stored = @[];
    }
    return [stored mutableCopy] ?: [NSMutableArray new];
}

- (void)saveMappings:(NSArray<NSDictionary<NSString *, id> *> *)mappings {
    [NSUserDefaults.standardUserDefaults setObject:mappings forKey:kFLEXLocalMapMappingsDefaultsKey];
}

- (NSArray<NSDictionary<NSString *, id> *> *)allMappings {
    return [self mutableMappings] ?: @[];
}

/// URLs are matched on scheme + host + path so query strings don't break a rule.
+ (NSString *)keyForURL:(NSURL *)url {
    return [self normalizeURL:url];
}

+ (NSString *)normalizeURL:(NSURL *)url {
    if (!url) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.query = nil;
    components.fragment = nil;

    NSString *string = components.string;
    // Strip a trailing slash so "/path" and "/path/" map identically.
    while (string.length > 1 && [string hasSuffix:@"/"]) {
        string = [string substringToIndex:string.length - 1];
    }
    return string.length ? string : nil;
}

/// Whether a mapping is considered enabled. Mappings written before the enabled
/// flag was introduced default to enabled.
+ (BOOL)mappingIsEnabled:(NSDictionary<NSString *, id> *)mapping {
    NSNumber *enabled = mapping[@"enabled"];
    return enabled ? enabled.boolValue : YES;
}

#pragma mark - Querying

- (nullable NSString *)localFilePathForURL:(NSURL *)url {
    NSString *key = [[self class] normalizeURL:url];
    if (!key.length) {
        return nil;
    }

    for (NSDictionary<NSString *, id> *mapping in self.allMappings) {
        if ([mapping[@"url"] isEqualToString:key]) {
            if (![[self class] mappingIsEnabled:mapping]) {
                continue;
            }

            NSString *file = mapping[@"file"];
            if (file.length && [NSFileManager.defaultManager fileExistsAtPath:file]) {
                return file;
            }
        }
    }
    return nil;
}

- (BOOL)hasMappingForURL:(NSURL *)url {
    return [self localFilePathForURL:url] != nil;
}

#pragma mark - Mutating

- (void)setMappingForURLString:(NSString *)urlString toFilePath:(NSString *)filePath {
    if (!urlString.length || !filePath.length) {
        return;
    }

    NSString *key = [[self class] normalizeURL:[NSURL URLWithString:urlString]];
    if (!key.length) {
        return;
    }

    // Preserve the previous enabled state when replacing an existing rule.
    BOOL enabled = YES;
    for (NSDictionary<NSString *, id> *mapping in self.allMappings) {
        if ([mapping[@"url"] isEqualToString:key]) {
            enabled = [[self class] mappingIsEnabled:mapping];
            break;
        }
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *mappings = [self mutableMappings];
    [mappings removeObjectURL:key];
    [mappings addObject:@{
        @"url" : key,
        @"file" : filePath,
        @"enabled" : @(enabled),
    }];
    [self saveMappings:mappings];
}

- (void)setEnabled:(BOOL)enabled forURLString:(NSString *)urlString {
    NSString *key = [[self class] normalizeURL:[NSURL URLWithString:urlString]];
    if (!key.length) {
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *mappings = [self mutableMappings];
    NSInteger index = [mappings indexOfObjectPassingTest:^BOOL(NSDictionary<NSString *, id> *mapping, NSUInteger idx, BOOL *stop) {
        return [mapping[@"url"] isEqualToString:key];
    }];

    if (index != NSNotFound) {
        NSMutableDictionary<NSString *, id> *updated = [mappings[index] mutableCopy];
        updated[@"enabled"] = @(enabled);
        mappings[index] = updated;
        [self saveMappings:mappings];
    }
}

- (void)removeMappingForURLString:(NSString *)urlString {
    NSString *key = [[self class] normalizeURL:[NSURL URLWithString:urlString]];
    if (!key.length) {
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *mappings = [self mutableMappings];
    [mappings removeObjectURL:key];
    [self saveMappings:mappings];
}

- (void)removeAllMappings {
    [self saveMappings:@[]];
}

#pragma mark - Files

- (NSArray<NSString *> *)localFilesInDocuments {
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES
    ).firstObject;
    if (!documents) {
        return @[];
    }

    NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:documents error:nil];
    if (!contents) {
        return @[];
    }

    NSMutableArray<NSString *> *files = [NSMutableArray new];
    for (NSString *name in contents) {
        NSString *path = [documents stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
            [files addObject:path];
        }
    }
    return [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (nullable NSString *)createLocalFileWithBaseName:(NSString *)baseName {
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES
    ).firstObject;
    if (!documents) {
        return nil;
    }

    NSString *name = baseName.length ? baseName : @"response.txt";
    NSString *base = [name stringByDeletingPathExtension];
    NSString *extension = [name pathExtension];
    NSString *path = [documents stringByAppendingPathComponent:name];
    NSFileManager *fileManager = NSFileManager.defaultManager;

    NSUInteger counter = 2;
    while ([fileManager fileExistsAtPath:path]) {
        NSString *candidate = extension.length
            ? [NSString stringWithFormat:@"%@-%lu.%@", base, (unsigned long)counter, extension]
            : [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)counter];
        path = [documents stringByAppendingPathComponent:candidate];
        counter++;
    }

    [fileManager createFileAtPath:path contents:[NSData data] attributes:nil];
    return path;
}

- (NSString *)mimeTypeForFile:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    static NSDictionary<NSString *, NSString *> *types = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        types = @{
            @"json" : @"application/json",
            @"txt"  : @"text/plain",
            @"text" : @"text/plain",
            @"html" : @"text/html",
            @"htm"  : @"text/html",
            @"css"  : @"text/css",
            @"js"   : @"application/javascript",
            @"xml"  : @"application/xml",
            @"plist": @"application/xml",
            @"png"  : @"image/png",
            @"jpg"  : @"image/jpeg",
            @"jpeg" : @"image/jpeg",
            @"gif"  : @"image/gif",
            @"webp" : @"image/webp",
            @"svg"  : @"image/svg+xml",
            @"pdf"  : @"application/pdf",
            @"mp4"  : @"video/mp4",
            @"mp3"  : @"audio/mpeg",
            @"wasm" : @"application/wasm",
        };
    });
    return types[ext] ?: @"application/octet-stream";
}

@end

/// Private helpers to keep the no-duplicates bookkeeping short.
@implementation NSMutableArray (FLEXLocalMapManager)

- (void)removeObjectURL:(NSString *)key {
    NSIndexSet *indexes = [self indexesOfObjectsPassingTest:^BOOL(NSDictionary<NSString *, id> *mapping, NSUInteger idx, BOOL *stop) {
        return [mapping[@"url"] isEqualToString:key];
    }];
    if (indexes.count > 0) {
        [self removeObjectsAtIndexes:indexes];
    }
}

@end
