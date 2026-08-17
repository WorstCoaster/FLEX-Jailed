//
//  FLEXLocalMappingURLProtocol.m
//  FLEX
//
//  Created for the "Map Local" network feature.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import "FLEXLocalMappingURLProtocol.h"
#import "FLEXLocalMapManager.h"

@implementation FLEXLocalMappingURLProtocol

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSURLProtocol registerClass:[FLEXLocalMappingURLProtocol class]];
    });
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL *url = request.URL;
    if (!url) {
        return NO;
    }
    
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }
    
    return [FLEXLocalMapManager.sharedManager hasMappingForURL:url];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *path = [FLEXLocalMapManager.sharedManager localFilePathForURL:self.request.URL];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileReadNoSuchFileError
                                         userInfo:@{NSFilePathErrorKey : path ?: @""}];
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }
    
    NSString *mimeType = [FLEXLocalMapManager.sharedManager mimeTypeForFile:path];
    NSDictionary<NSString *, NSString *> *headers = @{
        @"Content-Type" : mimeType,
        @"Content-Length" : @(data.length).stringValue,
        @"X-FLEX-Map-Local" : path.lastPathComponent ?: @"",
    };
    
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
        initWithURL:self.request.URL
        statusCode:200
        HTTPVersion:@"HTTP/1.1"
        headerFields:headers
    ];
    
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // Nothing to cancel; loading is synchronous.
}

@end