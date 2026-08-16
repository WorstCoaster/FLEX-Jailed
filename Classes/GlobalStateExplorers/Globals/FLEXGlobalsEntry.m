//
//  FLEXGlobalsEntry.m
//  FLEX
//
//  Created by Javier Soto on 7/26/14.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXGlobalsEntry.h"

@implementation FLEXGlobalsEntry

+ (instancetype)entryWithEntry:(Class<FLEXGlobalsEntry>)cls row:(FLEXGlobalsRow)row {
    BOOL providesVCs = [cls respondsToSelector:@selector(globalsEntryViewController:)];
    BOOL providesActions = [cls respondsToSelector:@selector(globalsEntryRowAction:)];
    NSParameterAssert(cls);
    NSParameterAssert(providesVCs || providesActions);

    FLEXGlobalsEntry *entry = [self new];
    entry->_entryNameFuture = ^{ return [cls globalsEntryTitle:row]; };
    entry->_iconName = [self flex_symbolNameForRow:row];

    if (providesVCs) {
        id action = providesActions ? [cls globalsEntryRowAction:row] : nil;
        if (action) {
            entry->_rowAction = action;
        } else {
            entry->_viewControllerFuture = ^{ return [cls globalsEntryViewController:row]; };
        }
    } else {
        entry->_rowAction = [cls globalsEntryRowAction:row];
    }

    return entry;
}

+ (instancetype)entryWithNameFuture:(FLEXGlobalsEntryNameFuture)nameFuture
               viewControllerFuture:(FLEXGlobalsEntryViewControllerFuture)viewControllerFuture {
    NSParameterAssert(nameFuture);
    NSParameterAssert(viewControllerFuture);

    FLEXGlobalsEntry *entry = [self new];
    entry->_entryNameFuture = [nameFuture copy];
    entry->_viewControllerFuture = [viewControllerFuture copy];

    return entry;
}

+ (instancetype)entryWithNameFuture:(FLEXGlobalsEntryNameFuture)nameFuture
                             action:(FLEXGlobalsEntryRowAction)rowSelectedAction {
    NSParameterAssert(nameFuture);
    NSParameterAssert(rowSelectedAction);

    FLEXGlobalsEntry *entry = [self new];
    entry->_entryNameFuture = [nameFuture copy];
    entry->_rowAction = [rowSelectedAction copy];

    return entry;
}

@end

@interface FLEXGlobalsEntry (Debugging)
@property (nonatomic, readonly) NSString *name;
@end

@implementation FLEXGlobalsEntry (Debugging)

- (NSString *)name {
    return self.entryNameFuture();
}

@end

#pragma mark - SF Symbol names

@implementation FLEXGlobalsEntry (Symbols)

+ (NSString *)flex_symbolNameForRow:(FLEXGlobalsRow)row {
    switch (row) {
        case FLEXGlobalsRowProcessInfo:       return @"info.circle";
        case FLEXGlobalsRowNetworkHistory:    return @"network";
        case FLEXGlobalsRowSystemLog:         return @"doc.text.magnifyingglass";
        case FLEXGlobalsRowLiveObjects:       return @"cube.box";
        case FLEXGlobalsRowAddressInspector:  return @"magnifyingglass";
        case FLEXGlobalsRowCookies:           return @"tag";
        case FLEXGlobalsRowBrowseRuntime:     return @"books.vertical";
        case FLEXGlobalsRowAppKeychainItems:  return @"lock.shield";
        case FLEXGlobalsRowPushNotifications: return @"bell.badge";
        case FLEXGlobalsRowAppDelegate:       return @"person.crop.circle";
        case FLEXGlobalsRowRootViewController:return @"square.stack";
        case FLEXGlobalsRowUserDefaults:      return @"slider.horizontal.3";
        case FLEXGlobalsRowMainBundle:        return @"cube";
        case FLEXGlobalsRowBrowseBundle:      return @"folder";
        case FLEXGlobalsRowBrowseContainer:   return @"tray";
        case FLEXGlobalsRowApplication:       return @"app";
        case FLEXGlobalsRowKeyWindow:         return @"rectangle.on.rectangle";
        case FLEXGlobalsRowMainScreen:        return @"display";
        case FLEXGlobalsRowCurrentDevice:     return @"iphone";
        case FLEXGlobalsRowPasteboard:        return @"doc.on.clipboard";
        case FLEXGlobalsRowURLSession:        return @"arrow.triangle.2.circlepath";
        case FLEXGlobalsRowURLCache:          return @"clock.arrow.circlepath";
        case FLEXGlobalsRowNotificationCenter:return @"bell";
        case FLEXGlobalsRowMenuController:    return @"ellipsis.circle";
        case FLEXGlobalsRowFileManager:       return @"folder.fill";
        case FLEXGlobalsRowTimeZone:          return @"clock";
        case FLEXGlobalsRowLocale:            return @"globe";
        case FLEXGlobalsRowCalendar:          return @"calendar";
        case FLEXGlobalsRowMainRunLoop:       return @"arrow.clockwise";
        case FLEXGlobalsRowMainThread:        return @"arrow.up.and.down";
        case FLEXGlobalsRowOperationQueue:    return @"tray.2";

        case FLEXGlobalsRowCount: break;
    }

    return nil;
}

@end

#pragma mark - flex_concreteGlobalsEntry

@implementation NSObject (FLEXGlobalsEntry)

+ (FLEXGlobalsEntry *)flex_concreteGlobalsEntry:(FLEXGlobalsRow)row {
    if ([self conformsToProtocol:@protocol(FLEXGlobalsEntry)]) {
        return [FLEXGlobalsEntry entryWithEntry:self row:row];
    }

    return nil;
}

@end
