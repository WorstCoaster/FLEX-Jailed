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
@property (nonatomic) UISearchController *searchController;

@end

@implementation FLEXStringPickerViewController

+ (instancetype)options:(NSArray<NSString *> *)options
                  title:(NSString *)title
             completion:(void(^)(NSString *value))completion {
    FLEXStringPickerViewController *picker = [self new];
    picker.options = options;
    picker.completion = completion;
    picker.title = title.length ? title : @"Choose";
    return picker;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
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
