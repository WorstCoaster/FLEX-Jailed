//
//  FLEXStringPickerViewController.m
//  FLEX
//
//  Created for the selector/value suggestion pool.
//  Copyright (c) 2026 FLEX Team. All rights reserved.
//

#import "FLEXStringPickerViewController.h"
#import "FLEXColor.h"

@interface FLEXStringPickerViewController () <UISearchResultsUpdating>

@property (nonatomic) NSArray<NSString *> *options;
@property (nonatomic, copy) void (^completion)(NSString *value);
@property (nonatomic, copy) void (^optionsProvider)(void(^done)(NSArray<NSString *> *values));
@property (nonatomic) UISearchController *searchController;

@end

@implementation FLEXStringPickerViewController

+ (instancetype)options:(NSArray<NSString *> *)options
                  title:(NSString *)title
             completion:(void(^)(NSString *value))completion {
    return [self options:options
                   title:title
         optionsProvider:nil
              completion:completion];
}

+ (instancetype)options:(NSArray<NSString *> *)options
                  title:(NSString *)title
        optionsProvider:(nullable void(^)(void(^done)(NSArray<NSString *> *values)))optionsProvider
             completion:(void(^)(NSString *value))completion {
    FLEXStringPickerViewController *picker = [self new];
    picker.options = options ?: @[];
    picker.optionsProvider = optionsProvider;
    picker.completion = completion;
    picker.title = title.length ? title : @"Choose";
    return picker;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    // Inset grouped matches the iOS 26 system list style.
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.backgroundColor = FLEXColor.groupedBackgroundColor;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    if (self.optionsProvider) {
        [self setLoadingAdditionalOptions:YES];
        self.optionsProvider(^(NSArray<NSString *> *moreOptions) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendOptions:moreOptions];
            });
        });
    }
}

- (void)appendOptions:(NSArray<NSString *> *)moreOptions {
    if (moreOptions.count == 0) {
        [self setLoadingAdditionalOptions:NO];
        return;
    }

    NSMutableOrderedSet<NSString *> *merged = [NSMutableOrderedSet orderedSetWithArray:self.options];
    [merged addObjectsFromArray:moreOptions];
    self.options = [[merged array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    [self setLoadingAdditionalOptions:NO];
    [self.tableView reloadData];
}

- (void)setLoadingAdditionalOptions:(BOOL)loading {
    if (loading) {
        UIView *footer = [UIView new];
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium
        ];
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [footer addSubview:spinner];
        [NSLayoutConstraint activateConstraints:@[
            [spinner.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
            [spinner.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        ]];
        footer.frame = CGRectMake(0, 0, 0, 44);
        [spinner startAnimating];
        self.tableView.tableFooterView = footer;
    } else {
        self.tableView.tableFooterView = nil;
    }
}

- (NSArray<NSString *> *)filteredOptions {
    NSString *filter = self.searchController.searchBar.text;
    if (filter.length == 0) {
        return self.options;
    }

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF CONTAINS[c] %@", filter];
    return [self.options filteredArrayUsingPredicate:predicate];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = self.filteredOptions.count;
    return count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"FLEXStringPickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        cell.textLabel.textColor = FLEXColor.primaryTextColor;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
        cell.backgroundColor = FLEXColor.primaryBackgroundColor;
    }

    NSArray<NSString *> *options = self.filteredOptions;
    if (options.count == 0) {
        cell.textLabel.text = @"No matches";
        return cell;
    }

    cell.textLabel.text = options[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray<NSString *> *options = self.filteredOptions;
    if (options.count == 0) {
        return;
    }

    if (self.completion) {
        self.completion(options[indexPath.row]);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self.tableView reloadData];
}

@end
