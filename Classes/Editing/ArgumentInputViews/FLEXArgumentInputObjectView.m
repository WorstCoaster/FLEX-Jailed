//
//  FLEXArgumentInputJSONObjectView.m
//  Flipboard
//
//  Created by Ryan Olson on 6/15/14.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXArgumentInputObjectView.h"
#import "FLEXRuntimeUtility.h"
#import "FLEXUtility.h"
#import "FLEXColor.h"
#import "FLEXObjectPickerViewController.h"

static const CGFloat kSegmentInputMargin = 10;
static const CGFloat kInstancePickerHeight = 32;

typedef NS_ENUM(NSUInteger, FLEXArgInputObjectType) {
    FLEXArgInputObjectTypeJSON,
    FLEXArgInputObjectTypeAddress,
    FLEXArgInputObjectTypeInstance
};

@interface FLEXArgumentInputObjectView ()

@property (nonatomic) UISegmentedControl *objectTypeSegmentControl;
@property (nonatomic) FLEXArgInputObjectType inputType;

@property (nonatomic) UIButton *instanceButton;
@property (nonatomic) UILabel *instanceLabel;
@property (nonatomic) id selectedInstance;

@end

@implementation FLEXArgumentInputObjectView

- (instancetype)initWithArgumentTypeEncoding:(const char *)typeEncoding {
    self = [super initWithArgumentTypeEncoding:typeEncoding];
    if (self) {
        // Start with the numbers and punctuation keyboard since quotes, curly braces, or
        // square brackets are likely to be the first characters type for the JSON.
        self.inputTextView.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        self.targetSize = FLEXArgumentInputViewSizeLarge;

        BOOL canPickInstance = [FLEXObjectPickerViewController canPickInstancesOfTypeEncoding:typeEncoding];
        NSArray<NSString *> *items = canPickInstance ?
            @[@"Value", @"Address", @"Instance"] :
            @[@"Value", @"Address"];

        self.objectTypeSegmentControl = [[UISegmentedControl alloc] initWithItems:items];
        [self.objectTypeSegmentControl addTarget:self action:@selector(didChangeType) forControlEvents:UIControlEventValueChanged];
        self.objectTypeSegmentControl.selectedSegmentIndex = 0;
        [self addSubview:self.objectTypeSegmentControl];

        self.instanceButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.instanceButton.tintColor = FLEXColor.tintColor;
        self.instanceButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.instanceButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [self.instanceButton setImage:[UIImage systemImageNamed:@"list.bullet"] forState:UIControlStateNormal];
        [self.instanceButton setTitle:@" Choose instance" forState:UIControlStateNormal];
        [self.instanceButton addTarget:self action:@selector(instanceButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.instanceButton];

        self.instanceLabel = [UILabel new];
        self.instanceLabel.font = [UIFont systemFontOfSize:13];
        self.instanceLabel.textColor = FLEXColor.deemphasizedTextColor;
        self.instanceLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:self.instanceLabel];

        self.inputType = [[self class] preferredDefaultTypeForObjCType:typeEncoding withCurrentValue:nil];
        // When we defaulted to the instance pool, the segment control may not
        // have been given a valid selection yet.
        if (self.objectTypeSegmentControl.numberOfSegments > self.inputType) {
            self.objectTypeSegmentControl.selectedSegmentIndex = self.inputType;
        }
        [self updateSubviewsForInputType];
    }

    return self;
}

- (void)didChangeType {
    self.inputType = (FLEXArgInputObjectType)self.objectTypeSegmentControl.selectedSegmentIndex;
    [self updateSubviewsForInputType];

    if (self.inputType == FLEXArgInputObjectTypeInstance) {
        [self updateInstanceControls];
    } else if (super.inputValue) {
        // Trigger an update to the text field to show
        // the address of the stored object we were given,
        // or to show a JSON representation of the object
        [self populateTextAreaFromValue:super.inputValue];
    } else {
        // Clear the text field
        [self populateTextAreaFromValue:nil];
    }
}

- (void)updateSubviewsForInputType {
    BOOL isInstance = self.inputType == FLEXArgInputObjectTypeInstance;
    self.instanceButton.hidden = !isInstance;
    self.instanceLabel.hidden = !isInstance;
    self.inputTextView.editable = !isInstance;

    [self setNeedsLayout];
    [self.superview setNeedsLayout];
}

- (void)setInputType:(FLEXArgInputObjectType)inputType {
    if (_inputType == inputType) return;

    _inputType = inputType;

    // Resize input view
    switch (inputType) {
        case FLEXArgInputObjectTypeJSON:
            self.targetSize = FLEXArgumentInputViewSizeLarge;
            break;
        case FLEXArgInputObjectTypeAddress:
            self.targetSize = FLEXArgumentInputViewSizeSmall;
            break;
        case FLEXArgInputObjectTypeInstance:
            self.targetSize = FLEXArgumentInputViewSizeDefault;
            break;
    }

    // Change placeholder
    switch (inputType) {
        case FLEXArgInputObjectTypeJSON:
            self.inputPlaceholderText =
            @"You can put any valid JSON here, such as a string, number, array, or dictionary:"
            "\n\"This is a string\""
            "\n1234"
            "\n{ \"name\": \"Bob\", \"age\": 47 }"
            "\n["
            "\n   1, 2, 3"
            "\n]";
            break;
        case FLEXArgInputObjectTypeAddress:
            self.inputPlaceholderText = @"0x0000deadb33f";
            break;
        case FLEXArgInputObjectTypeInstance:
            self.inputPlaceholderText = nil;
            break;
    }

    [self updateSubviewsForInputType];
    [self setNeedsLayout];
}

- (void)setInputValue:(id)inputValue {
    super.inputValue = inputValue;
    if (self.inputType == FLEXArgInputObjectTypeInstance) {
        self.selectedInstance = inputValue;
        [self updateInstanceControls];
    } else {
        [self populateTextAreaFromValue:inputValue];
    }
}

- (id)inputValue {
    switch (self.inputType) {
        case FLEXArgInputObjectTypeJSON:
            return [FLEXRuntimeUtility objectValueFromEditableJSONString:self.inputTextView.text];
        case FLEXArgInputObjectTypeAddress: {
            NSScanner *scanner = [NSScanner scannerWithString:self.inputTextView.text];

            unsigned long long objectPointerValue;
            if ([scanner scanHexLongLong:&objectPointerValue]) {
                return (__bridge id)(void *)objectPointerValue;
            }

            return nil;
        }
        case FLEXArgInputObjectTypeInstance:
            return self.selectedInstance;
    }
}

- (void)populateTextAreaFromValue:(id)value {
    if (!value) {
        self.inputTextView.text = nil;
    } else if (self.inputType == FLEXArgInputObjectTypeJSON) {
        self.inputTextView.text = [FLEXRuntimeUtility editableJSONStringForObject:value];
    } else {
        // Address and Instance modes both display the object pointer
        self.inputTextView.text = [NSString stringWithFormat:@"%p", value];
    }

    // Delegate methods are not called for programmatic changes
    [self textViewDidChange:self.inputTextView];
}

- (void)updateInstanceControls {
    if (self.selectedInstance) {
        [self.instanceButton setTitle:@" Change instance" forState:UIControlStateNormal];

        NSString *className = [FLEXRuntimeUtility safeClassNameForObject:self.selectedInstance];
        NSString *summary = [FLEXRuntimeUtility summaryForObject:self.selectedInstance];
        if (summary.length) {
            self.instanceLabel.text = [NSString stringWithFormat:@"%@ %p — %@",
                className, self.selectedInstance, summary
            ];
        } else {
            self.instanceLabel.text = [NSString stringWithFormat:@"%@ %p", className, self.selectedInstance];
        }
    } else {
        [self.instanceButton setTitle:@" Choose instance" forState:UIControlStateNormal];
        self.instanceLabel.text = @"No instance selected";
    }

    [self populateTextAreaFromValue:self.selectedInstance];
}

- (void)instanceButtonTapped:(UIButton *)sender {
    NSString *className = [FLEXObjectPickerViewController classNameFromTypeEncoding:self.typeEncoding.UTF8String];

    void (^completion)(id object) = ^(id object) {
        self.selectedInstance = object;
        [self updateInstanceControls];
        [self.delegate argumentInputViewValueDidChange:self];
    };

    FLEXObjectPickerViewController *picker;
    if (className.length > 0) {
        picker = [FLEXObjectPickerViewController pickerForClassName:className completion:completion];
    } else {
        // Plain `id` arguments have no class hint; offer every live object.
        picker = [FLEXObjectPickerViewController pickerForAnyObjectWithCompletion:completion];
    }

    UIViewController *host = [FLEXUtility nearestViewControllerForView:self];
    [host.navigationController pushViewController:picker animated:YES];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fitSize = [super sizeThatFits:size];
    fitSize.height += [self.objectTypeSegmentControl sizeThatFits:size].height + kSegmentInputMargin;

    if (self.inputType == FLEXArgInputObjectTypeInstance) {
        fitSize.height += kInstancePickerHeight + kSegmentInputMargin;
    }

    return fitSize;
}

- (void)layoutSubviews {
    CGFloat segmentHeight = [self.objectTypeSegmentControl sizeThatFits:self.frame.size].height;
    self.objectTypeSegmentControl.frame = CGRectMake(
        0.0,
        // Our segmented control is taking the position
        // of the text view, as far as super is concerned,
        // and we override this property to be different
        super.topInputFieldVerticalLayoutGuide,
        self.frame.size.width,
        segmentHeight
    );

    if (self.inputType == FLEXArgInputObjectTypeInstance) {
        CGFloat pickerY = CGRectGetMaxY(self.objectTypeSegmentControl.frame) + kSegmentInputMargin;
        CGSize buttonSize = [self.instanceButton sizeThatFits:self.frame.size];
        CGFloat buttonWidth = MIN(buttonSize.width + 24, self.frame.size.width * 0.5);

        self.instanceButton.frame = CGRectMake(0, pickerY, buttonWidth, kInstancePickerHeight);
        self.instanceLabel.frame = CGRectMake(
            CGRectGetMaxX(self.instanceButton.frame) + kSegmentInputMargin,
            pickerY,
            self.frame.size.width - CGRectGetMaxX(self.instanceButton.frame) - kSegmentInputMargin,
            kInstancePickerHeight
        );
    }

    [super layoutSubviews];
}

- (CGFloat)topInputFieldVerticalLayoutGuide {
    // Our text view is offset from the segmented control
    CGFloat segmentHeight = [self.objectTypeSegmentControl sizeThatFits:self.frame.size].height;
    CGFloat guide = segmentHeight + super.topInputFieldVerticalLayoutGuide + kSegmentInputMargin;

    if (self.inputType == FLEXArgInputObjectTypeInstance) {
        guide += kInstancePickerHeight + kSegmentInputMargin;
    }

    return guide;
}

+ (BOOL)supportsObjCType:(const char *)type withCurrentValue:(id)value {
    NSParameterAssert(type);
    // Must be object type
    return type[0] == FLEXTypeEncodingObjcObject || type[0] == FLEXTypeEncodingObjcClass;
}

+ (FLEXArgInputObjectType)preferredDefaultTypeForObjCType:(const char *)type withCurrentValue:(id)value {
    NSParameterAssert(type[0] == FLEXTypeEncodingObjcObject || type[0] == FLEXTypeEncodingObjcClass);

    if (value) {
        // If there's a current value, it must be serializable to JSON
        // to display the JSON editor. Otherwise display the address field.
        if ([FLEXRuntimeUtility editableJSONStringForObject:value]) {
            return FLEXArgInputObjectTypeJSON;
        } else {
            return FLEXArgInputObjectTypeAddress;
        }
    } else {
        // No current value: prefer the instance pool when we know the class,
        // so the available options are immediately visible.
        if ([FLEXObjectPickerViewController canPickInstancesOfTypeEncoding:type]) {
            return FLEXArgInputObjectTypeInstance;
        }

        // Otherwise, see if we have more type information than just 'id'.
        // If we do, make sure the encoding is something serializable to JSON.
        // Properties and ivars keep more detailed type encoding information than method arguments.
        if (strcmp(type, @encode(id)) != 0) {
            BOOL isJSONSerializableType = NO;

            // Parse class name out of the string,
            // which is in the form `@"ClassName"`
            Class cls = NSClassFromString(({
                NSString *className = nil;
                NSScanner *scan = [NSScanner scannerWithString:@(type)];
                NSCharacterSet *allowed = [NSCharacterSet
                    characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"
                ];

                // Skip over the @" then scan the name
                if ([scan scanString:@"@\"" intoString:nil]) {
                    [scan scanCharactersFromSet:allowed intoString:&className];
                }

                className;
            }));

            // Note: we can't use @encode(NSString) here because that drops
            // the class information and just goes to @encode(id).
            NSArray<Class> *jsonTypes = @[
                [NSString class],
                [NSNumber class],
                [NSArray class],
                [NSDictionary class],
            ];

            // Look for matching types
            for (Class jsonClass in jsonTypes) {
                if ([cls isSubclassOfClass:jsonClass]) {
                    isJSONSerializableType = YES;
                    break;
                }
            }

            if (isJSONSerializableType) {
                return FLEXArgInputObjectTypeJSON;
            } else {
                return FLEXArgInputObjectTypeAddress;
            }
        } else {
            return FLEXArgInputObjectTypeAddress;
        }
    }
}

@end
