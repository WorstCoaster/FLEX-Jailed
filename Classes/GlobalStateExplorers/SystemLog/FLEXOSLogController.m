//
//  FLEXOSLogController.m
//  FLEX
//
//  Created by Tanner on 12/19/18.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "FLEXOSLogController.h"
#import "NSUserDefaults+FLEX.h"
#import <objc/message.h>
#include <dlfcn.h>
#include <string.h>
#include "ActivityStreamAPI.h"

static os_activity_stream_for_pid_t OSActivityStreamForPID;
static os_activity_stream_resume_t OSActivityStreamResume;
static os_activity_stream_cancel_t OSActivityStreamCancel;
static os_log_copy_formatted_message_t OSLogCopyFormattedMessage;
static os_activity_stream_set_event_handler_t OSActivityStreamSetEventHandler;
static int (*proc_name)(int, char *, unsigned int);
static int (*proc_listpids)(uint32_t, uint32_t, void*, int);
static uint8_t (*OSLogGetType)(void *);

/// Shadow interface for LoggingSupport's OSActivityEvent wrapper.
///
/// On modern iOS the raw activity stream structs changed layout, so reading
/// `log_message` fields directly (or calling os_log_copy_formatted_message with
/// our legacy struct definition) can dereference garbage and crash the host
/// process. LoggingSupport ships an Objective-C wrapper that knows the current
/// layout and composes the message safely. We declare it here for type checking
/// only; the class is looked up at runtime so the dylib doesn't link against the
/// private framework.
@interface FLEXOSActivityEvent : NSObject
@property (nonatomic, copy) NSString *eventMessage;
@property (nonatomic, readonly) NSDate *timestamp;
@end


@interface FLEXOSLogController ()

+ (FLEXOSLogController *)sharedLogController;

@property (nonatomic) void (^updateHandler)(NSArray<FLEXSystemLogMessage *> *);

@property (nonatomic) BOOL canPrint;
@property (nonatomic) int filterPid;
@property (nonatomic) BOOL levelInfo;
@property (nonatomic) BOOL subsystemInfo;

@property (nonatomic) os_activity_stream_t stream;

- (NSString *)messageTextForEntry:(os_activity_stream_entry_t)entry date:(NSDate **)outDate;

@end

@implementation FLEXOSLogController

+ (void)load {
    // Persist logs when the app launches on iOS 10 if we have persistent logs turned on
    if (FLEXOSLogAvailable()) {
        if (NSUserDefaults.standardUserDefaults.flex_cacheOSLogMessages) {
            [self sharedLogController].persistent = YES;
            [[self sharedLogController] startMonitoring];
        }
    }
}

+ (instancetype)sharedLogController {
    static FLEXOSLogController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [self new];
    });
    
    return shared;
}

+ (instancetype)withUpdateHandler:(void(^)(NSArray<FLEXSystemLogMessage *> *newMessages))newMessagesHandler {
    FLEXOSLogController *shared = [self sharedLogController];
    shared.updateHandler = newMessagesHandler;
    return shared;
}

- (id)init {
    NSAssert(FLEXOSLogAvailable(), @"os_log is only available on iOS 10 and up");

    self = [super init];
    if (self) {
        _filterPid = NSProcessInfo.processInfo.processIdentifier;
        _levelInfo = NO;
        _subsystemInfo = NO;
    }
    
    return self;
}

- (void)dealloc {
    OSActivityStreamCancel(self.stream);
    _stream = nil;
}

- (void)setPersistent:(BOOL)persistent {
    if (_persistent == persistent) return;
    
    _persistent = persistent;
    self.messages = persistent ? [NSMutableArray new] : nil;
}

- (BOOL)startMonitoring {
    if (![self lookupSPICalls]) {
        // >= iOS 10 is required
        return NO;
    }
    
    // Are we already monitoring?
    if (self.stream) {
        // Should we send out the "persisted" messages?
        if (self.updateHandler && self.messages.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.updateHandler(self.messages);
            });
        }
        
        return YES;
    }

    // Stream entry handler
    os_activity_stream_block_t block = ^bool(os_activity_stream_entry_t entry, int error) {
        return [self handleStreamEntry:entry error:error];
    };

    // Controls which types of messages we see
    // 'Historical' appears to just show NSLog stuff
    uint32_t activity_stream_flags = OS_ACTIVITY_STREAM_HISTORICAL;
    activity_stream_flags |= OS_ACTIVITY_STREAM_PROCESS_ONLY;
//    activity_stream_flags |= OS_ACTIVITY_STREAM_PROCESS_ONLY;

    self.stream = OSActivityStreamForPID(self.filterPid, activity_stream_flags, block);

    // Specify the stream-related event handler
    OSActivityStreamSetEventHandler(self.stream, [self streamEventHandlerBlock]);
    // Start the stream
    OSActivityStreamResume(self.stream);

    return YES;
}

- (BOOL)lookupSPICalls {
    static BOOL hasSPI = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/LoggingSupport.framework/LoggingSupport", RTLD_NOW);

        OSActivityStreamForPID = (os_activity_stream_for_pid_t)dlsym(handle, "os_activity_stream_for_pid");
        OSActivityStreamResume = (os_activity_stream_resume_t)dlsym(handle, "os_activity_stream_resume");
        OSActivityStreamCancel = (os_activity_stream_cancel_t)dlsym(handle, "os_activity_stream_cancel");
        OSLogCopyFormattedMessage = (os_log_copy_formatted_message_t)dlsym(handle, "os_log_copy_formatted_message");
        OSActivityStreamSetEventHandler = (os_activity_stream_set_event_handler_t)dlsym(handle, "os_activity_stream_set_event_handler");
        proc_name = (int(*)(int, char *, unsigned int))dlsym(handle, "proc_name");
        proc_listpids = (int(*)(uint32_t, uint32_t, void*, int))dlsym(handle, "proc_listpids");
        OSLogGetType = (uint8_t(*)(void *))dlsym(handle, "os_log_get_type");

        hasSPI = (OSActivityStreamForPID != NULL) &&
                (OSActivityStreamResume != NULL) &&
                (OSActivityStreamCancel != NULL) &&
                (OSLogCopyFormattedMessage != NULL) &&
                (OSActivityStreamSetEventHandler != NULL) &&
                (OSLogGetType != NULL) &&
                (proc_name != NULL);
    });
    
    return hasSPI;
}

- (BOOL)handleStreamEntry:(os_activity_stream_entry_t)entry error:(int)error {
    if (!self.canPrint || (self.filterPid != -1 && entry->pid != self.filterPid)) {
        return YES;
    }

    if (!error && entry) {
        if (entry->type == OS_ACTIVITY_STREAM_TYPE_LOG_MESSAGE ||
            entry->type == OS_ACTIVITY_STREAM_TYPE_LEGACY_LOG_MESSAGE) {
            NSDate *date = nil;
            NSString *msg = [self messageTextForEntry:entry date:&date] ?: @"";

            dispatch_async(dispatch_get_main_queue(), ^{
                FLEXSystemLogMessage *message = [FLEXSystemLogMessage logMessageFromDate:date text:msg];
                if (self.persistent) {
                    [self.messages addObject:message];
                }
                if (self.updateHandler) {
                    self.updateHandler(@[message]);
                }
            });
        }
    }
    
    return YES;
}

/// Uses LoggingSupport's OSActivityEvent wrapper when available, since its
/// struct definitions match the running OS. On older iOS where the wrapper
/// doesn't exist, fall back to the legacy struct path. See
/// https://github.com/FLEXTool/FLEX/issues/564 and
/// https://github.com/FLEXTool/FLEX/issues/717
- (NSString *)messageTextForEntry:(os_activity_stream_entry_t)entry date:(NSDate **)outDate {
    static Class OSActivityEventClass = nil;
    static SEL makeEventSEL = NULL;
    static BOOL hasWrapper = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OSActivityEventClass = NSClassFromString(@"OSActivityEvent");
        makeEventSEL = NSSelectorFromString(@"activityEventFromStreamEntry:");
        hasWrapper = OSActivityEventClass != nil &&
                     makeEventSEL != NULL &&
                     [OSActivityEventClass respondsToSelector:makeEventSEL];
    });

    if (hasWrapper) {
        FLEXOSActivityEvent *event = ((id (*)(id, SEL, os_activity_stream_entry_t))objc_msgSend)(
            OSActivityEventClass, makeEventSEL, entry
        );
        if (event) {
            NSDate *date = event.timestamp;
            if (outDate) {
                *outDate = [date isKindOfClass:[NSDate class]] ? date : [NSDate date];
            }

            NSString *text = event.eventMessage;
            return [text isKindOfClass:[NSString class]] ? text : @"";
        }

        // The wrapper exists, so the legacy struct layout is unsafe to touch.
        // Prefer an empty row over dereferencing a stale struct and crashing.
        if (outDate) {
            *outDate = [NSDate date];
        }
        return @"";
    }

    // Fallback for older iOS where the wrapper class isn't available.
    os_log_message_t log_message = &entry->log_message;
    if (outDate) {
        *outDate = [NSDate dateWithTimeIntervalSince1970:log_message->tv_gmt.tv_sec];
    }

    if (OSLogCopyFormattedMessage) {
        const char *formatted = OSLogCopyFormattedMessage(log_message);
        if (formatted != NULL && formatted[0] != '\0' &&
            strncmp(formatted, "<compose failure", 16) != 0) {
            return [NSString stringWithUTF8String:formatted];
        }
    }

    if (log_message->format != NULL) {
        return [NSString stringWithUTF8String:log_message->format];
    }

    return @"";
}

- (os_activity_stream_event_block_t)streamEventHandlerBlock {
    return [^void(os_activity_stream_t stream, os_activity_stream_event_t event) {
        switch (event) {
            case OS_ACTIVITY_STREAM_EVENT_STARTED:
                self.canPrint = YES;
                break;
            case OS_ACTIVITY_STREAM_EVENT_STOPPED:
                break;
            case OS_ACTIVITY_STREAM_EVENT_FAILED:
                break;
            case OS_ACTIVITY_STREAM_EVENT_CHUNK_STARTED:
                break;
            case OS_ACTIVITY_STREAM_EVENT_CHUNK_FINISHED:
                break;
            default:
                printf("=== Unhandled case ===\n");
                break;
        }
    } copy];
}

@end
