//
//  FLEXDylibEntry.m
//  FLEX
//
//  Created for dylib injection support
//  This file provides the entry point when FLEX is injected as a dylib
//
//  Modernized: initialization is idempotent (dispatch_once), so loading
//  the dylib twice can never double-swizzle UIApplication. Works on
//  scene-based (iOS 13+) apps, since all touches still flow through
//  -[UIApplication sendEvent:].
//

#import "FLEXManager.h"
#import "FLEXUtility.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface FLEXDylibEntry : NSObject
+ (void)initializeFLEX;
+ (void)setupGestureRecognizer;
@end

@implementation FLEXDylibEntry

static const NSTimeInterval gestureHoldDuration = 0.5; // Hold for 0.5 seconds
static NSTimer *gestureTimer = nil;
static BOOL gestureInProgress = NO;

+ (void)initializeFLEX {
    // Never swizzle more than once, even if the dylib is injected twice
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Wait a bit for the app to fully initialize
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try {
                // Don't show FLEX automatically - wait for gesture
                [self setupGestureRecognizer];

                // Log that FLEX was injected successfully
                NSLog(@"[FLEX] Successfully injected - hold 3 fingers to toggle");
            } @catch (NSException *exception) {
                NSLog(@"[FLEX] Error initializing: %@", exception);
            }
        });
    });
}

+ (void)setupGestureRecognizer {
    // Swizzle UIApplication's sendEvent: to detect 3-finger touches
    SEL originalSelector = @selector(sendEvent:);
    SEL swizzledSelector = [FLEXUtility swizzledSelectorForSelector:originalSelector];

    void (^sendEventBlock)(UIApplication *, UIEvent *) = ^(UIApplication *slf, UIEvent *event) {
        if (event.type == UIEventTypeTouches) {
            NSSet<UITouch *> *allTouches = [event allTouches];
            NSInteger touchCount = [allTouches count];

            // Count active touches (began, moved, or stationary)
            NSInteger activeTouchCount = 0;
            for (UITouch *touch in allTouches) {
                if (touch.phase == UITouchPhaseBegan ||
                    touch.phase == UITouchPhaseMoved ||
                    touch.phase == UITouchPhaseStationary) {
                    activeTouchCount++;
                }
            }

            // If exactly 3 fingers are down and gesture not already triggered
            if (activeTouchCount == 3 && !gestureInProgress) {
                // Check if all touches are active (not ended or cancelled)
                BOOL allActive = YES;
                for (UITouch *touch in allTouches) {
                    if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                        allActive = NO;
                        break;
                    }
                }

                // Start timer if not already running and all touches are active
                if (allActive && gestureTimer == nil) {
                    gestureInProgress = YES;
                    __weak typeof(self) weakSelf = self;
                    gestureTimer = [NSTimer scheduledTimerWithTimeInterval:gestureHoldDuration
                                                                    repeats:NO
                                                                      block:^(NSTimer *timer) {
                        [weakSelf handleThreeFingerGesture];
                    }];
                    [[NSRunLoop mainRunLoop] addTimer:gestureTimer forMode:NSRunLoopCommonModes];
                }
            } else if (activeTouchCount != 3) {
                // Cancel timer if touch count changes
                [self cancelGestureTimer];
            }
        }

        // Call original implementation
        ((void(*)(id, SEL, id))objc_msgSend)(slf, swizzledSelector, event);
    };

    [FLEXUtility replaceImplementationOfKnownSelector:originalSelector
                                              onClass:[UIApplication class]
                                            withBlock:sendEventBlock
                                     swizzledSelector:swizzledSelector];
}

+ (void)cancelGestureTimer {
    if (gestureTimer != nil) {
        [gestureTimer invalidate];
        gestureTimer = nil;
    }
    gestureInProgress = NO;
}

+ (void)handleThreeFingerGesture {
    // Invalidate timer
    [self cancelGestureTimer];

    // Toggle FLEX
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            FLEXManager *manager = [FLEXManager sharedManager];
            if ([manager isHidden]) {
                [manager showExplorer];
                NSLog(@"[FLEX] Shown via 3-finger gesture");
            } else {
                [manager hideExplorer];
                NSLog(@"[FLEX] Hidden via 3-finger gesture");
            }
        } @catch (NSException *exception) {
            NSLog(@"[FLEX] Error toggling: %@", exception);
        }
    });
}

@end

// Constructor that runs when the dylib is loaded
__attribute__((constructor))
static void FLEXDylibInit(void) {
    // Ensure we're on the main thread for UI operations
    if ([NSThread isMainThread]) {
        [FLEXDylibEntry initializeFLEX];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [FLEXDylibEntry initializeFLEX];
        });
    }
}
