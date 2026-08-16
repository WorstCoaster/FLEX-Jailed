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

@interface FLEXObjectPickerViewController () <UISearchResultsUpdating>

@property (nonatomic) NSString *className;
@property (nonatomic) Class targetClass;
@property (nonatomic, copy) void (^completion)(id object);
@property (nonatomic) NSArray<FLEXObjectRef *> *instances;
@property (nonatomic) NSArray<FLEXObjectRef *> *knownInstances;
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

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;

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
    self.instances = [self collectInstances];
}

#pragma mark - Instance collection

- (NSArray<FLEXObjectRef *> *)collectInstances {
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
    return [FLEXObjectRef referencingAll:objects retained:YES];
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
            [refs addObject:[FLEXObjectRef unretained:object ivar:label]];
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
    self.instances = [self collectInstances];
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

- (NSArray<FLEXObjectRef *> *)filteredInstances {
    NSString *filter = self.filterText;
    if (!filter) {
        return self.instances;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(FLEXObjectRef *ref, NSDictionary *bindings) {
        return [ref.reference localizedCaseInsensitiveContainsString:filter] ||
               [ref.summary localizedCaseInsensitiveContainsString:filter];
    }];
    return [self.instances filteredArrayUsingPredicate:predicate];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.filteredKnownInstances.count > 0 ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 && self.filteredKnownInstances.count > 0) {
        return self.filteredKnownInstances.count;
    }
    return self.filteredInstances.count ?: 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && self.filteredKnownInstances.count > 0) {
        return @"Known";
    }
    return @"Live instances";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSInteger liveSection = self.filteredKnownInstances.count > 0 ? 1 : 0;
    if (section == liveSection && self.truncated) {
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

    if (indexPath.section == 0 && self.filteredKnownInstances.count > 0) {
        FLEXObjectRef *ref = self.filteredKnownInstances[indexPath.row];
        cell.textLabel.text = ref.reference;
        cell.detailTextLabel.text = ref.summary;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (self.filteredInstances.count == 0) {
        cell.textLabel.text = @"No live instances found";
        cell.detailTextLabel.text = @"Tap to rescan the heap";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    FLEXObjectRef *ref = self.filteredInstances[indexPath.row];
    cell.textLabel.text = ref.reference;
    cell.detailTextLabel.text = ref.summary;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    FLEXObjectRef *ref = nil;
    if (indexPath.section == 0 && self.filteredKnownInstances.count > 0) {
        ref = self.filteredKnownInstances[indexPath.row];
    } else if (self.filteredInstances.count == 0) {
        [self rescan];
        return;
    } else if (indexPath.row < self.filteredInstances.count) {
        ref = self.filteredInstances[indexPath.row];
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
