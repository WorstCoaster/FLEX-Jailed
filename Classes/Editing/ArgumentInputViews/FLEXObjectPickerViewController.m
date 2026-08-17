//
//  FLEXObjectPickerViewController.m
//  FLEX
//
//  Created for the instance-picker argument input.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXObjectPickerViewController.h"
#import "FLEXHeapEnumerator.h"
#import "FLEXRuntimeUtility.h"
#import "FLEXUtility.h"
#import "FLEXColor.h"
#import "FLEXWindow.h"
#import <malloc/malloc.h>
#import <objc/runtime.h>

/// Upper bound on the total number of entries surfaced in the picker.
static const NSUInteger kFLEXObjectPickerMaxResults = 200;
/// Upper bound on the on-demand heap scan when no relevant instances are found.
static const NSUInteger kFLEXObjectPickerHeapFallbackLimit = 100;

/// A single live instance the user can pick.
///
/// Objects collected from the host app's reachable object graph are retained so
/// they stay valid while the picker is on screen. Objects discovered by the raw
/// heap scan are intentionally *not* retained: retaining arbitrary heap objects
/// (libdispatch internals, for example) can crash the process.
@interface FLEXObjectPickerEntry : NSObject
@property (nonatomic) NSString *className;
@property (nonatomic, unsafe_unretained) id object;
/// Non-nil when the object is safely owned by the app and may be retained.
@property (nonatomic, strong) id retainer;
@property (nonatomic) NSString *reference;
@property (nonatomic) NSString *summary;
@end

@implementation FLEXObjectPickerEntry
@end


/// A named group of live instances that all share the same concrete class.
@interface FLEXObjectPickerGroup : NSObject
@property (nonatomic) NSString *className;
@property (nonatomic) NSArray<FLEXObjectPickerEntry *> *objects;
@end

@implementation FLEXObjectPickerGroup
@end


@interface FLEXObjectPickerViewController () <UISearchResultsUpdating>

@property (nonatomic) NSString *className;
@property (nonatomic) Class targetClass;
@property (nonatomic, copy) void (^completion)(id object);
@property (nonatomic) NSArray<FLEXObjectPickerEntry *> *knownInstances;
@property (nonatomic) NSArray<FLEXObjectPickerGroup *> *instanceGroups;
/// Raw-heap results, populated only after the user explicitly requests a scan.
@property (nonatomic) NSArray<FLEXObjectPickerGroup *> *heapGroups;
@property (nonatomic) BOOL didScanHeap;
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
    if (typeEncoding == NULL) {
        return NO;
    }

    // `@` (id) and `@"ClassName"` both enumerate to live objects. `#` (Class)
    // is intentionally excluded: class objects are not necessarily heap
    // allocations, so a heap scan would silently omit most of them.
    return typeEncoding[0] == FLEXTypeEncodingObjcObject;
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

+ (instancetype)pickerForAnyObjectWithCompletion:(void(^)(id object))completion {
    FLEXObjectPickerViewController *picker = [self new];
    picker.className = nil;
    picker.targetClass = NULL;
    picker.completion = completion;
    picker.title = @"Objects";
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
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = [FLEXUtility glassBackgroundView];

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

#pragma mark - Matching

- (BOOL)class:(Class)cls matchesTargetClass:(Class)target {
    if (target == NULL) {
        return YES;
    }

    Class cursor = cls;
    while (cursor != NULL) {
        if (cursor == target) {
            return YES;
        }
        cursor = class_getSuperclass(cursor);
    }

    return NO;
}

+ (NSString *)safeSummaryForObject:(id)object {
    @try {
        return [FLEXRuntimeUtility summaryForObject:object] ?: @"";
    } @catch (NSException *exception) {
        return @"";
    }
}

#pragma mark - Relevant instance collection

/// Collects instances reachable from the host app's live UI/object graph
/// (windows, view controllers, views, layers, gestures, and the app/delegate
/// roots). These are the instances most likely to be the one the user wants,
/// and they are safe to retain because the app still owns them.
///
/// FLEX's own window (and everything beneath it) is skipped, so the debugger's
/// UI never pollutes the list of candidate instances.
- (NSArray<FLEXObjectPickerEntry *> *)collectRelevantInstances {
    NSMutableArray<FLEXObjectPickerEntry *> *entries = [NSMutableArray new];
    NSMutableSet<NSValue *> *seen = [NSMutableSet new];
    __block NSUInteger remaining = kFLEXObjectPickerMaxResults;

    __block void (^explore)(id object);
    explore = ^(id object) {
        if (!object || remaining == 0) {
            return;
        }

        // Skip FLEX's window before it reaches the host-app object graph.
        if ([object isKindOfClass:[FLEXWindow class]]) {
            return;
        }

        NSValue *box = [NSValue valueWithPointer:(__bridge const void *)object];
        if ([seen containsObject:box]) {
            return;
        }
        [seen addObject:box];

        if ([self class:object_getClass(object) matchesTargetClass:self.targetClass]) {
            FLEXObjectPickerEntry *entry = [FLEXObjectPickerEntry new];
            entry.className = NSStringFromClass(object_getClass(object));
            entry.object = object;
            entry.retainer = object;
            entry.reference = [NSString stringWithFormat:@"%@ %p", entry.className, object];
            entry.summary = [[self class] safeSummaryForObject:object];
            [entries addObject:entry];
            remaining--;
        }

        if ([object isKindOfClass:[UIWindow class]]) {
            explore(((UIWindow *)object).rootViewController);
        } else if ([object isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)object;
            explore(vc.view);
            explore(vc.presentedViewController);
            for (UIViewController *child in vc.childViewControllers) {
                explore(child);
            }
            explore(vc.parentViewController);
            explore(vc.navigationController);
            explore(vc.tabBarController);
        } else if ([object isKindOfClass:[UIView class]]) {
            UIView *view = (UIView *)object;
            for (UIView *subview in view.subviews) {
                explore(subview);
            }
            explore(view.layer);
            explore([FLEXUtility viewControllerForView:view]);
            for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
                explore(gesture);
            }
        } else if ([object isKindOfClass:[CALayer class]]) {
            CALayer *layer = (CALayer *)object;
            for (CALayer *sublayer in layer.sublayers) {
                explore(sublayer);
            }
            explore(layer.delegate);
        } else if ([object isKindOfClass:[UIApplication class]]) {
            UIApplication *app = (UIApplication *)object;
            explore(app.delegate);
            for (UIWindow *window in app.windows) {
                explore(window);
            }
        }
    };

    // The app root reaches its delegate and every app window (FLEX's window is
    // filtered out inside the block above).
    explore(UIApplication.sharedApplication);

    // Break the recursive block's retain cycle before returning.
    explore = nil;

    return entries;
}

/// Bounded raw-heap scan used only when the user explicitly asks for it. Entries
/// are left unretained and never messaged, since arbitrary heap objects are not
/// guaranteed to be safe to retain or describe.
- (NSArray<FLEXObjectPickerGroup *> *)collectHeapGroups {
    Class targetClass = self.targetClass;
    if (targetClass == NULL) {
        return @[];
    }

    NSMutableArray<FLEXObjectPickerEntry *> *entries = [NSMutableArray new];
    NSMutableSet<NSValue *> *seen = [NSMutableSet new];

    [FLEXHeapEnumerator enumerateLiveObjectsUsingBlock:^(
        __unsafe_unretained id object, __unsafe_unretained Class actualClass
    ) {
        if (entries.count >= kFLEXObjectPickerHeapFallbackLimit) {
            return;
        }
        if (actualClass == NULL) {
            return;
        }
        if (![self class:actualClass matchesTargetClass:targetClass]) {
            return;
        }
        if (malloc_size((__bridge const void *)object) == 0) {
            return;
        }

        NSValue *box = [NSValue valueWithPointer:(__bridge const void *)object];
        if ([seen containsObject:box]) {
            return;
        }
        [seen addObject:box];

        FLEXObjectPickerEntry *entry = [FLEXObjectPickerEntry new];
        entry.className = @(class_getName(actualClass));
        entry.object = object;      // unretained on purpose
        entry.reference = [NSString stringWithFormat:@"%@ %p", entry.className, object];
        entry.summary = nil;
        [entries addObject:entry];
    }];

    if (entries.count == 0) {
        return @[];
    }

    FLEXObjectPickerGroup *group = [FLEXObjectPickerGroup new];
    group.className = NSStringFromClass(targetClass);
    group.objects = entries;
    return @[group];
}

- (NSArray<FLEXObjectPickerGroup *> *)collectInstanceGroups {
    NSArray<FLEXObjectPickerEntry *> *relevant = [self collectRelevantInstances];

    NSMutableDictionary<NSString *, NSMutableArray<FLEXObjectPickerEntry *> *> *byClass = [NSMutableDictionary new];
    NSMutableOrderedSet<NSString *> *classOrder = [NSMutableOrderedSet new];
    for (FLEXObjectPickerEntry *entry in relevant) {
        NSMutableArray<FLEXObjectPickerEntry *> *groupEntries = byClass[entry.className];
        if (!groupEntries) {
            groupEntries = [NSMutableArray new];
            byClass[entry.className] = groupEntries;
            [classOrder addObject:entry.className];
        }
        [groupEntries addObject:entry];
    }

    NSMutableArray<NSString *> *orderedNames = [[classOrder.array
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] mutableCopy];

    // Surface the requested class first so the most common pick is at the top.
    if (self.targetClass != NULL) {
        NSString *targetName = NSStringFromClass(self.targetClass);
        if ([orderedNames containsObject:targetName]) {
            [orderedNames removeObject:targetName];
            [orderedNames insertObject:targetName atIndex:0];
        }
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
/// listed above the live instances so common values are one tap away.
- (NSArray<FLEXObjectPickerEntry *> *)collectKnownInstances {
    Class targetClass = self.targetClass;
    BOOL matchAny = (targetClass == NULL);

    NSMutableArray<FLEXObjectPickerEntry *> *entries = [NSMutableArray new];
    NSHashTable *seen = [NSHashTable weakObjectsHashTable];

    void (^add)(id object, NSString *label) = ^(id object, NSString *label) {
        if (!object || [seen containsObject:object]) {
            return;
        }
        [seen addObject:object];
        if (matchAny || [FLEXRuntimeUtility safeObject:object isKindOfClass:targetClass]) {
            FLEXObjectPickerEntry *entry = [FLEXObjectPickerEntry new];
            entry.className = NSStringFromClass(object_getClass(object));
            entry.object = object;
            entry.retainer = object;
            entry.reference = [NSString stringWithFormat:@"%@ · %@", entry.className, label];
            entry.summary = [[self class] safeSummaryForObject:object];
            [entries addObject:entry];
        }
    };

    UIApplication *app = UIApplication.sharedApplication;
    add(app, @"sharedApplication");
    add(app.delegate, @"delegate");

    UIWindow *keyWindow = FLEXUtility.appKeyWindow;
    add(keyWindow, @"keyWindow");
    add(keyWindow.rootViewController, @"keyWindow.rootViewController");

    for (UIWindow *window in app.windows) {
        // Skip the debugger's own window; it is never a useful pick.
        if ([window isKindOfClass:[FLEXWindow class]]) {
            continue;
        }
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

    return entries;
}

- (void)rescan {
    self.knownInstances = [self collectKnownInstances];
    self.instanceGroups = [self collectInstanceGroups];
    self.heapGroups = nil;
    self.didScanHeap = NO;
    [self.tableView reloadData];
}

- (void)scanHeap {
    self.heapGroups = [self collectHeapGroups];
    self.didScanHeap = YES;
    [self.tableView reloadData];
}

#pragma mark - Filtering

- (NSString *)filterText {
    NSString *text = self.searchController.searchBar.text;
    return text.length ? text : nil;
}

- (NSArray<FLEXObjectPickerEntry *> *)filteredKnownInstances {
    NSString *filter = self.filterText;
    if (!filter) {
        return self.knownInstances;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(FLEXObjectPickerEntry *entry, NSDictionary *bindings) {
        return [entry.reference localizedCaseInsensitiveContainsString:filter] ||
               [entry.summary localizedCaseInsensitiveContainsString:filter];
    }];
    return [self.knownInstances filteredArrayUsingPredicate:predicate];
}

- (NSArray<FLEXObjectPickerGroup *> *)filteredGroups:(NSArray<FLEXObjectPickerGroup *> *)groups {
    NSString *filter = self.filterText;
    if (!filter) {
        return groups;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(FLEXObjectPickerEntry *entry, NSDictionary *bindings) {
        return [entry.reference localizedCaseInsensitiveContainsString:filter] ||
               [entry.summary localizedCaseInsensitiveContainsString:filter];
    }];

    NSMutableArray<FLEXObjectPickerGroup *> *filtered = [NSMutableArray new];
    for (FLEXObjectPickerGroup *group in groups) {
        NSArray<FLEXObjectPickerEntry *> *matching = [group.objects filteredArrayUsingPredicate:predicate];
        if (matching.count > 0) {
            FLEXObjectPickerGroup *copy = [FLEXObjectPickerGroup new];
            copy.className = group.className;
            copy.objects = matching;
            [filtered addObject:copy];
        }
    }

    return filtered;
}

- (NSArray<FLEXObjectPickerGroup *> *)filteredLiveGroups {
    return [self filteredGroups:self.instanceGroups];
}

- (NSArray<FLEXObjectPickerGroup *> *)filteredHeapGroups {
    return [self filteredGroups:self.heapGroups];
}

/// The groups shown in the "instances" area: reachable UI instances when any
/// match, otherwise the on-demand heap results.
- (NSArray<FLEXObjectPickerGroup *> *)displayGroups {
    NSArray<FLEXObjectPickerGroup *> *live = self.filteredLiveGroups;
    if (live.count > 0) {
        return live;
    }
    return self.filteredHeapGroups;
}

- (BOOL)isShowingHeapResults {
    return self.filteredLiveGroups.count == 0 &&
           self.didScanHeap &&
           self.filteredHeapGroups.count > 0;
}

- (BOOL)showsKnownSection {
    return self.filteredKnownInstances.count > 0;
}

- (NSInteger)liveSectionOffset {
    return self.showsKnownSection ? 1 : 0;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = self.showsKnownSection ? 1 : 0;
    NSArray<FLEXObjectPickerGroup *> *groups = self.displayGroups;
    sections += groups.count > 0 ? groups.count : 1; // Always at least the empty state.
    return sections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.showsKnownSection && section == 0) {
        return self.filteredKnownInstances.count;
    }

    NSArray<FLEXObjectPickerGroup *> *groups = self.displayGroups;
    if (groups.count == 0) {
        return 1; // Empty-state row.
    }

    NSInteger liveIndex = section - self.liveSectionOffset;
    return groups[liveIndex].objects.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.showsKnownSection && section == 0) {
        return @"Known";
    }

    NSArray<FLEXObjectPickerGroup *> *groups = self.displayGroups;
    if (groups.count == 0) {
        return @"Instances";
    }

    FLEXObjectPickerGroup *group = groups[section - self.liveSectionOffset];
    return [NSString stringWithFormat:@"%@ (%@)", group.className, @(group.objects.count)];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == self.tableView.numberOfSections - 1) {
        if (self.isShowingHeapResults) {
            return @"No UI instances matched this type. These heap instances are not retained and may be unstable.";
        }
        if (self.filteredLiveGroups.count > 0) {
            return @"Showing instances reachable from the app's current UI. Use search to narrow the results.";
        }
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
        cell.backgroundColor = UIColor.clearColor;
    }

    if (self.showsKnownSection && indexPath.section == 0) {
        FLEXObjectPickerEntry *entry = self.filteredKnownInstances[indexPath.row];
        cell.textLabel.text = entry.reference;
        cell.detailTextLabel.text = entry.summary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    NSArray<FLEXObjectPickerGroup *> *groups = self.displayGroups;
    if (groups.count == 0) {
        if (self.filterText.length > 0) {
            cell.textLabel.text = @"No matching instances";
            cell.detailTextLabel.text = @"Clear the search to browse all instances";
        } else if (!self.didScanHeap) {
            cell.textLabel.text = @"No instances in the app's UI";
            cell.detailTextLabel.text = @"Tap to scan the heap for matches";
        } else {
            cell.textLabel.text = @"No matching instances found";
            cell.detailTextLabel.text = @"Tap to rescan";
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    FLEXObjectPickerGroup *group = groups[indexPath.section - self.liveSectionOffset];
    FLEXObjectPickerEntry *entry = group.objects[indexPath.row];
    cell.textLabel.text = entry.reference;
    cell.detailTextLabel.text = entry.summary;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    FLEXObjectPickerEntry *entry = nil;
    if (self.showsKnownSection && indexPath.section == 0) {
        entry = self.filteredKnownInstances[indexPath.row];
    } else {
        NSArray<FLEXObjectPickerGroup *> *groups = self.displayGroups;
        if (groups.count == 0) {
            // Only trigger collection when there is actually nothing to show;
            // a search mismatch should not start an expensive scan.
            if (self.filterText.length == 0) {
                if (self.didScanHeap) {
                    [self rescan];
                } else {
                    [self scanHeap];
                }
            }
            return;
        }

        FLEXObjectPickerGroup *group = groups[indexPath.section - self.liveSectionOffset];
        if (indexPath.row < group.objects.count) {
            entry = group.objects[indexPath.row];
        }
    }

    if (!entry) {
        return;
    }

    id object = entry.object;
    BOOL isValid = entry.retainer != nil ||
        [FLEXRuntimeUtility pointerIsValidObjcObject:(__bridge const void *)object];
    if (!isValid) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Instance unavailable"
            message:@"That instance was deallocated. Rescanning for a fresh list."
            preferredStyle:UIAlertControllerStyleAlert
        ];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self rescan];
        return;
    }

    if (self.completion) {
        self.completion(object);
    }

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self.tableView reloadData];
}

@end
