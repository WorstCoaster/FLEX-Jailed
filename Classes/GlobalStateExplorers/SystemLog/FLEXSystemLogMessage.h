//
//  FLEXSystemLogMessage.h
//  FLEX
//
//  Created by Ryan Olson on 1/25/15.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <asl.h>
#import "ActivityStreamAPI.h"

NS_ASSUME_NONNULL_BEGIN

@interface FLEXSystemLogMessage : NSObject

+ (instancetype)logMessageFromASLMessage:(aslmsg)aslMessage;
+ (instancetype)logMessageFromDate:(NSDate *)date text:(NSString *)text;
+ (instancetype)logMessageFromDate:(NSDate *)date
                              text:(NSString *)text
                           process:(nullable NSString *)process
                         subsystem:(nullable NSString *)subsystem
                          category:(nullable NSString *)category;

// ASL specific properties
@property (nonatomic, readonly, nullable) NSString *sender;
@property (nonatomic, readonly, nullable) aslmsg aslMessage;

@property (nonatomic, readonly) NSDate *date;
@property (nonatomic, readonly) NSString *messageText;
@property (nonatomic, readonly) long long messageID;

// OSLog (unified log) metadata; nil for ASL messages
@property (nonatomic, readonly, nullable) NSString *process;
@property (nonatomic, readonly, nullable) NSString *subsystem;
@property (nonatomic, readonly, nullable) NSString *category;

@end

NS_ASSUME_NONNULL_END
