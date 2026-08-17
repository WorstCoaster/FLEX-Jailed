//
//  FLEXSwiftBridge.m
//  FLEX
//
//  Created as the ObjC ↔ Swift bridge for the SwiftUI surfaces.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import "FLEXSwiftBridge.h"
#import "FLEXHeapEnumerator.h"
#import "FLEXObjectListViewController.h"
#import "FLEXLocalMapManager.h"

@implementation FLEXSwiftBridge

#pragma mark - Heap Objects

+ (void)beginHeapScanWithProgress:(void (^)(double))progress
                       completion:(void (^)(NSArray<NSString *> *,
                                            NSDictionary<NSString *, NSNumber *> *,
                                            NSDictionary<NSString *, NSNumber *> *))completion {
    if (!completion) {
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        FLEXHeapSnapshot *snapshot = [FLEXHeapEnumerator generateHeapSnapshotWithProgress:^(double p) {
            if (progress) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progress(p);
                });
            }
        }];
        
        NSArray<NSString *> *names = snapshot.classNames ?: @[];
        NSDictionary<NSString *, NSNumber *> *counts = snapshot.instanceCountsForClassNames ?: @{};
        NSDictionary<NSString *, NSNumber *> *sizes = snapshot.instanceSizesForClassNames ?: @{};
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(names, counts, sizes);
        });
    });
}

+ (void)pushInstancesOfClass:(NSString *)className from:(UIViewController *)host {
    if (!className.length || !host) {
        return;
    }
    
    UIViewController *list = [FLEXObjectListViewController instancesOfClassWithName:className retained:YES];
    if (!list) {
        return;
    }
    
    if (host.navigationController) {
        [host.navigationController pushViewController:list animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
        [host presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark - Map Local

+ (NSArray<NSDictionary<NSString *, id> *> *)localMappings {
    return FLEXLocalMapManager.sharedManager.allMappings;
}

+ (void)setLocalMappingForURL:(NSString *)url toFile:(NSString *)path {
    [FLEXLocalMapManager.sharedManager setMappingForURLString:url toFilePath:path];
}

+ (void)removeLocalMappingForURL:(NSString *)url {
    [FLEXLocalMapManager.sharedManager removeMappingForURLString:url];
}

+ (void)removeAllLocalMappings {
    [FLEXLocalMapManager.sharedManager removeAllMappings];
}

+ (void)setEnabled:(BOOL)enabled forLocalMappingURL:(NSString *)url {
    [FLEXLocalMapManager.sharedManager setEnabled:enabled forURLString:url];
}

+ (NSArray<NSString *> *)localFilesInDocuments {
    return FLEXLocalMapManager.sharedManager.localFilesInDocuments;
}

+ (nullable NSString *)createLocalFileWithBaseName:(NSString *)name {
    return [FLEXLocalMapManager.sharedManager createLocalFileWithBaseName:name];
}

+ (nullable NSString *)fileContentsAtPath:(NSString *)path {
    if (!path.length) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)writeContents:(NSString *)contents toFileAtPath:(NSString *)path {
    if (!path.length) {
        return NO;
    }
    NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return [data writeToFile:path atomically:YES];
}

+ (NSString *)mimeTypeForFile:(NSString *)path {
    return [FLEXLocalMapManager.sharedManager mimeTypeForFile:path];
}

@end