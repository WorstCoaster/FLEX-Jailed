//
//  FLEXNetworkTransactionCell.h
//  Flipboard
//
//  Created by Ryan Olson on 2/8/15.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FLEXNetworkTransaction;

@interface FLEXNetworkTransactionCell : UITableViewCell

@property (nonatomic) FLEXNetworkTransaction *transaction;
/// When YES, the details line gains a "Local Map" badge (set from the Map Local feature).
@property (nonatomic) BOOL isLocallyMapped;

@property (nonatomic, readonly, class) NSString *reuseID;
@property (nonatomic, readonly, class) CGFloat preferredCellHeight;

@end
