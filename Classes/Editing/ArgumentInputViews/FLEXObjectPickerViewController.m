//
//  FLEXObjectPickerViewController.m
//  FLEX
//
//  Created for the instance-picker argument input.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXObjectPickerViewController.h"
#import "FLEXHeapEnumerator.h"
#import "FLEXObjectRef.h"
#import "FLEXRuntimeUtility.h"
#import "FLEXUtility.h"
#import "FLEXColor.h"
#import <malloc/malloc.h>
#import <objc/runtime.h>

/// Keep the heap scan bounded. This is a picker, not a full object browser.
static const NSUInteger kFLEXObjectPickerMaxResults = 1000;

/// A named group of live instances that all share the same concrete class.
@interface FLEXObjectPickerGroup : NSObject
@property (nonatomic) NSString *className;
@property (nonatomic) NSArray<FLEXObjectRef *> *objects;
@end

@implementation FLEXObjectPickerGroup
@end


@interface FLEXObjectPickerViewController () <UISearchResultsUpdating>

@property (nonatomic) NSString *className;
@property (nonatomic) Class targetClass;
@property (nonatomic, copy) void (^completion)(id object);
@property (nonatomic) NSArray<FLEXObjectRef *> *knownInstances;
@property (nonatomic) NSArray<FLEXObjectPickerGroup *> *instanceGroups;
@property (nonatomic) BOOL truncated;
@property (nonatomic) UISearchController *searchController;

@end

@implementation FLEXObjectPickerViewController

+ (nullable NSString *)classNameFromTypeEncoding:(const char *)typeEncoding {
    if (typeEncoding == NULL || typeEncoding[0] != FLEXTypeEncodingObjcObject) {
        return nil;
    }

    // Object encodings are either `@` (id) or `@"ClassName"`.
    NSScanner *scanner = [NSScanner scannerWithString:@(typeEncoding)];
    if (![scanner scanString:@"@\"" intoString:nil]) {
        return nil;
    }

    NSCharacterSet *allowed = [NSCharacterSet
        characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"
    ];
    NSString *className = nil;
    if ([scanner scanCharactersFromSet:allowed intoString:&className] && className.length) {
        return className;
    }

    return nil;
}

+ (BOOL)canPickInstancesOfTypeEncoding:(const char *)typeEncoding {
    NSString *className = [self classNameFromTypeEncoding:typeEncoding];
    return className.length > 0 && NSClassFromString(className) != nil;
}

+ (instancetype)pickerForClassName:(NSString *)className
                        completion:(void(^)(id object))completion {
    FLEXObjectPickerViewController *picker = [self new];
    picker.className = className;
    picker.targetClass = NSClassFromString(className);
    picker.completion = completion;
    picker.title = [NSString stringWithFormat:@"%@ instances", className];
    return picker;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    // Inset grouped matches the iOS 26 system list style used throughout FLEX.
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    self.tableView.backgroundColor = FLEXColor.groupedBackgroundColor;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter instances";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self
        action:@selector(rescan)
    ];

    self.knownInstances = [self collectKnownInstances];
    self.instanceGroups = [self collectInstanceGroups];
}

#pragma mark - Instance collection

- (NSArray<FLEXObjectPickerGroup *> *)collectInstanceGroups {
    Class targetClass = self.targetClass;
    if (targetClass == NULL) {
        return @[];
    }

    NSMutableArray *objects = [NSMutableArray new];
    __block BOOL truncated = NO;

    [FLEXHeapEnumerator enumerateLiveObjectsUsingBlock:^(
        __unsafe_unretained id object, __unsafe_unretained Class actualClass
    ) {
        if (truncated) {
            return;
        }

        // Match the class or any subclass without messaging the object,
        // since heap candidates are only validated by their isa pointer.
        Class tryClass = actualClass;
        while (tryClass != NULL) {
            if (tryClass == targetClass) {
                if (malloc_size((__bridge const void *)object) > 0) {
                    if (objects.count < kFLEXObjectPickerMaxResults) {
                        [objects addObject:object];
                    } else {
                        truncated = YES;
                    }
                }
                break;
            }
            tryClass = class_getSuperclass(tryClass);
        }
    }];

    self.truncated = truncated;

    // Retain the heap objects for the lifetime of the picker, then group them
    // by concrete class so subclasses are easy to scan at a glance.
    NSArray<FLEXObjectRef *> *refs = [FLEXObjectRef referencingAll:objects retained:YES];
    NSMutableDictionary<NSString *, NSMutableArray<FLEXObjectRef *> *> *byClass = [NSMutableDictionary new];
    for (FLEXObjectRef *ref in refs) {
        NSString *className = [FLEXRuntimeUtility safeClassNameForObject:ref.object];
        NSMutableArray<FLEXObjectRef *> *group = byClass[className];
        if (!group) {
            group = [NSMutableArray new];
            byClass[className] = group;
        }
        [group addObject:ref];
    }

    NSMutableArray<NSString *> *orderedNames = [[byClass.allKeys
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] mutableCopy];

    // Surface the target class first so the most common pick is at the top.
    NSString *targetName = NSStringFromClass(targetClass);
    if ([orderedNames containsObject:targetName]) {
        [orderedNames removeObject:targetName];
        [orderedNames insertObject:targetName atIndex:0];
    }

    NSMutableArray<FLEXObjectPickerGroup *> *groups = [NSMutableArray new];
    for (NSString *name in orderedNames) {
        FLEXObjectPickerGroup *group = [FLEXObjectPickerGroup new];
        group.className = name;
        group.objects = byClass[name];
        [groups addObject:group];
    }

    return groups;
}

/// Well-known singletons and app objects that match the target class. These are
/// listed above the heap scan so common values are one tap away.
- (NSArray<FLEXObjectRef *> *)collectKnownInstances {
    Class targetClass = self.targetClass;
    if (targetClass == NULL) {
        return @[];
    }

    NSMutableArray<FLEXObjectRef *> *refs = [NSMutableArray new];
    NSHashTable *seen = [NSHashTable weakObjectsHashTable];

    void (^add)(id object, NSString *label) = ^(id object, NSString *label) {
        if (!object || [seen containsObject:object]) {
            return;
        }
        [seen addObject:object];
        if ([FLEXRuntimeUtility safeObject:object isKindOfClass:targetClass]) {
            // Retain these as well; window and root-view-controller references
            // can change while the picker is on screen.
            [refs addObject:[FLEXObjectRef retained:object ivar:label]];
        }
    };

    UIApplication *app = UIApplication.sharedApplication;
    add(app, @"sharedApplication");
    add(app.delegate, @"delegate");

    UIWindow *keyWindow = FLEXUtility.appKeyWindow;
    add(keyWindow, @"keyWindow");
    add(keyWindow.rootViewController, @"keyWindow.rootViewController");

    for (UIWindow *window in app.windows) {
        add(window, @"window");
        add(window.rootViewController, @"window.rootViewController");
    }

    add(NSNotificationCenter.defaultCenter, @"notificationCenter");
    add(NSUserDefaults.standardUserDefaults, @"standardUserDefaults");
    add(NSFileManager.defaultManager, @"defaultManager");
    add(UIScreen.mainScreen, @"mainScreen");
    add(UIDevice.currentDevice, @"currentDevice");
    add(NSBundle.mainBundle, @"mainBundle");
    add(UIPasteboard.generalPasteboard, @"generalPasteboard");
    add(NSProcessInfo.processInfo, @"processInfo");
    add(NSURLCache.sharedURLCache, @"sharedURLCache");

    return refs;
}

- (void)rescan {
    self.knownInstances = [self collectKnownInstances];
    self.instanceGroups = [self collectInstanceGroups];
    [self.tableView reloadData];
}

#pragma mark - Filtering

- (NSString *)filterText {
    NSString *text = self.searchController.searchBar.text;
    return text.length ? text : nil;
}

- (NSArray<FLEXObjectRef *> *)filteredKnownInstances {
    NSString *filter = self.filterText;
    if (!filter) {
        return self.knownInstances;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(FLEXObjectRef *ref, NSDictionary *bindings) {
        return [ref.reference localizedCaseInsensitiveContainsString:filter] ||
               [ref.summary localizedCaseInsensitiveContainsString:filter];
    }];
    return [self.knownInstances filteredArrayUsingPredicate:predicate];
}

- (NSArray<FLEXObjectPickerGroup *> *)filteredInstanceGroups {
    NSString *filter = self.filterText;
    if (!filter) {
        return self.instanceGroups;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(FLEXObjectRef *ref, NSDictionary *bindings) {
        return [ref.reference localizedCaseInsensitiveContainsString:filter] ||
               [ref.summary localizedCaseInsensitiveContainsString:filter];
    }];

    NSMutableArray<FLEXObjectPickerGroup *> *filtered = [NSMutableArray new];
    for (FLEXObjectPickerGroup *group in self.instanceGroups) {
        NSArray<FLEXObjectRef *> *matching = [group.objects filteredArrayUsingPredicate:predicate];
        if (matching.count > 0) {
            FLEXObjectPickerGroup *copy = [FLEXObjectPickerGroup new];
            copy.className = group.className;
            copy.objects = matching;
            [filtered addObject:copy];
        }
    }

    return filtered;
}

- (BOOL)showsKnownSection {
    return self.filteredKnownInstances.count > 0;
}

- (NSInteger)liveSectionOffset {
    return self.showsKnownSection ? 1 : 0;
}

- (NSArray<FLEXObjectPickerGroup *> *)liveGroups {
    return self.filteredInstanceGroups;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = self.liveGroups.count ?: 1; // Always at least the empty state.
    if (self.showsKnownSection) {
        sections += 1;
    }
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.showsKnownSection && section == 0) {
        return self.filteredKnownInstances.count;
    }

    if (self.liveGroups.count == 0) {
        return 1; // Empty-state row.
    }

    NSInteger liveIndex = section - self.liveSectionOffset;
    return self.liveGroups[liveIndex].objects.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.showsKnownSection && section == 0) {
        return @"Known";
    }

    if (self.liveGroups.count == 0) {
        return @"Live instances";
    }

    FLEXObjectPickerGroup *group = self.liveGroups[section - self.liveSectionOffset];
    return [NSString stringWithFormat:@"%@ (%@)", group.className, @(group.objects.count)];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.truncated && self.liveGroups.count > 0 &&
        section == self.tableView.numberOfSections - 1) {
        return [NSString stringWithFormat:
            @"Showing the first %@ live instances. Use search to narrow the results.",
            @(kFLEXObjectPickerMaxResults)
        ];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"FLEXObjectPickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.textLabel.textColor = FLEXColor.primaryTextColor;
        cell.detailTextLabel.textColor = FLEXColor.deemphasizedTextColor;
        cell.backgroundColor = FLEXColor.primaryBackgroundColor;
    }

    if (self.showsKnownSection && indexPath.section == 0) {
        FLEXObjectRef *ref = self.filteredKnownInstances[indexPath.row];
        cell.textLabel.text = ref.reference;
        cell.detailTextLabel.text = ref.summary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (self.liveGroups.count == 0) {
        if (self.filterText.length > 0) {
            cell.textLabel.text = @"No matching instances";
            cell.detailTextLabel.text = @"Clear the search to browse all instances";
        } else {
            cell.textLabel.text = @"No live instances found";
            cell.detailTextLabel.text = @"Tap to rescan the heap";
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    FLEXObjectPickerGroup *group = self.liveGroups[indexPath.section - self.liveSectionOffset];
    FLEXObjectRef *ref = group.objects[indexPath.row];
    cell.textLabel.text = ref.reference;
    cell.detailTextLabel.text = ref.summary;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    FLEXObjectRef *ref = nil;
    if (self.showsKnownSection && indexPath.section == 0) {
        ref = self.filteredKnownInstances[indexPath.row];
    } else if (self.liveGroups.count == 0) {
        // Only rescan when the heap is actually empty; a search mismatch
        // should not trigger an expensive heap walk.
        if (self.filterText.length == 0) {
            [self rescan];
        }
        return;
    } else {
        FLEXObjectPickerGroup *group = self.liveGroups[indexPath.section - self.liveSectionOffset];
        if (indexPath.row < group.objects.count) {
            ref = group.objects[indexPath.row];
        }
    }

    if (ref) {
        id object = ref.object;
        if (self.completion) {
            self.completion(object);
        }
    }

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self.tableView reloadData];
}

@end
