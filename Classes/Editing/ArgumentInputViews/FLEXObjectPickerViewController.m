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
#import <malloc/malloc.h>
#import <objc/runtime.h>

/// Keep the heap scan bounded. This is a picker, not a full object browser.
static const NSUInteger kFLEXObjectPickerMaxResults = 1000;

@interface FLEXObjectPickerViewController ()

@property (nonatomic) NSString *className;
@property (nonatomic) Class targetClass;
@property (nonatomic, copy) void (^completion)(id object);
@property (nonatomic) NSArray<FLEXObjectRef *> *instances;
@property (nonatomic) BOOL truncated;

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

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self
        action:@selector(rescan)
    ];

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

- (void)rescan {
    self.instances = [self collectInstances];
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.instances.count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"FLEXObjectPickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    if (self.instances.count == 0) {
        cell.textLabel.text = @"No live instances found";
        cell.detailTextLabel.text = @"Tap to rescan the heap";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    FLEXObjectRef *ref = self.instances[indexPath.row];
    cell.textLabel.text = ref.reference;
    cell.detailTextLabel.text = ref.summary;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.truncated) {
        return [NSString stringWithFormat:
            @"Showing the first %@ instances. Refine the search or explore Heap Objects for the rest.",
            @(kFLEXObjectPickerMaxResults)
        ];
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.instances.count == 0) {
        [self rescan];
        return;
    }

    if (indexPath.row < self.instances.count) {
        id object = self.instances[indexPath.row].object;
        if (self.completion) {
            self.completion(object);
        }
    }

    [self.navigationController popViewControllerAnimated:YES];
}

@end
