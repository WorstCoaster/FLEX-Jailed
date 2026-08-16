//
//  FLEXTableContentHeaderCell.m
//  FLEX
//
//  Created by Peng Tao on 15/11/26.
//  Copyright © 2015年 f. All rights reserved.
//

#import "FLEXTableColumnHeader.h"
#import "FLEXColor.h"
#import "UIFont+FLEX.h"
#import "FLEXUtility.h"

static const CGFloat kMargin = 5;
static const CGFloat kArrowWidth = 20;

@interface FLEXTableColumnHeader ()
@property (nonatomic, readonly) UIImageView *arrowView;
@property (nonatomic, readonly) UIView *lineView;
@end

@implementation FLEXTableColumnHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = FLEXColor.secondaryBackgroundColor;
        
        _titleLabel = [UILabel new];
        _titleLabel.font = UIFont.flex_defaultTableCellFont;
        [self addSubview:_titleLabel];
        
        _arrowView = [UIImageView new];
        _arrowView.tintColor = FLEXColor.iconColor;
        [self addSubview:_arrowView];
        
        _lineView = [UIView new];
        _lineView.backgroundColor = FLEXColor.hairlineColor;
        [self addSubview:_lineView];
        
    }
    return self;
}

- (void)setSortType:(FLEXTableColumnHeaderSortType)type {
    _sortType = type;
    
    // SF Symbol sort arrows (iOS 13+); older OSes simply show no arrow
    if (@available(iOS 13.0, *)) {
        switch (type) {
            case FLEXTableColumnHeaderSortTypeNone:
                _arrowView.image = nil;
                break;
            case FLEXTableColumnHeaderSortTypeAsc:
                _arrowView.image = [UIImage systemImageNamed:@"arrow.up"];
                break;
            case FLEXTableColumnHeaderSortTypeDesc:
                _arrowView.image = [UIImage systemImageNamed:@"arrow.down"];
                break;
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGSize size = self.frame.size;
    
    self.titleLabel.frame = CGRectMake(kMargin, 0, size.width - kArrowWidth - kMargin, size.height);
    self.arrowView.frame = CGRectMake(size.width - kArrowWidth, 0, kArrowWidth, size.height);
    self.lineView.frame = CGRectMake(size.width - 1, 2, FLEXPointsToPixels(1), size.height - 4);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat margins = kArrowWidth - 2 * kMargin;
    size = CGSizeMake(size.width - margins, size.height);
    CGFloat width = [_titleLabel sizeThatFits:size].width + margins;
    return CGSizeMake(width, size.height);
}

@end
