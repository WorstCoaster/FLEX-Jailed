//
//  FLEXGlobalsSection.m
//  FLEX
//
//  Created by Tanner Bennett on 7/11/19.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "FLEXGlobalsSection.h"
#import "FLEXColor.h"
#import "NSArray+FLEX.h"
#import "UIFont+FLEX.h"

@interface FLEXGlobalsSection ()
/// Filtered rows
@property (nonatomic) NSArray<FLEXGlobalsEntry *> *rows;
/// Unfiltered rows
@property (nonatomic) NSArray<FLEXGlobalsEntry *> *allRows;
@end
@implementation FLEXGlobalsSection

#pragma mark - Initialization

+ (instancetype)title:(NSString *)title rows:(NSArray<FLEXGlobalsEntry *> *)rows {
    FLEXGlobalsSection *s = [self new];
    s->_title = title;
    s.allRows = rows;

    return s;
}

- (void)setAllRows:(NSArray<FLEXGlobalsEntry *> *)allRows {
    _allRows = allRows.copy;
    [self reloadData];
}

#pragma mark - Overrides

- (NSInteger)numberOfRows {
    return self.rows.count;
}

- (void)setFilterText:(NSString *)filterText {
    super.filterText = filterText;
    [self reloadData];
}

- (void)reloadData {
    NSString *filterText = self.filterText;
    
    if (filterText.length) {
        self.rows = [self.allRows flex_filtered:^BOOL(FLEXGlobalsEntry *entry, NSUInteger idx) {
            return [entry.entryNameFuture() localizedCaseInsensitiveContainsString:filterText];
        }];
    } else {
        self.rows = self.allRows;
    }
}

- (BOOL)canSelectRow:(NSInteger)row {
    return YES;
}

- (void (^)(__kindof UIViewController *))didSelectRowAction:(NSInteger)row {
    return (id)self.rows[row].rowAction;
}

- (UIViewController *)viewControllerToPushForRow:(NSInteger)row {
    return self.rows[row].viewControllerFuture ? self.rows[row].viewControllerFuture() : nil;
}

- (void)configureCell:(__kindof UITableViewCell *)cell forRow:(NSInteger)row {
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.font = UIFont.flex_defaultTableCellFont;
    FLEXGlobalsEntry *entry = self.rows[row];
    cell.textLabel.text = entry.entryNameFuture();

    // SF Symbol icons (iOS 13+); plain rows render without an icon
    if (@available(iOS 13.0, *)) {
        NSString *symbolName = entry.iconName;
        UIImage *icon = symbolName.length ? [UIImage systemImageNamed:symbolName] : nil;
        cell.imageView.image = icon;
        cell.imageView.tintColor = FLEXColor.iconColor;
        // Match the text size; SF Symbol images are larger by default
        cell.imageView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } else {
        cell.imageView.image = nil;
    }
}

@end


@implementation FLEXGlobalsSection (Subscripting)

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
    return self.rows[idx];
}

@end
