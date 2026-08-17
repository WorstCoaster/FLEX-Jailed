//
//  FLEXFieldEditorViewController.m
//  FLEX
//
//  Created by Tanner on 11/22/18.
//  Copyright © 2020 FLEX Team. All rights reserved.
//

#import "FLEXFieldEditorViewController.h"
#import "FLEXFieldEditorView.h"
#import "FLEXArgumentInputViewFactory.h"
#import "FLEXArgumentInputStringView.h"
#import "FLEXPropertyAttributes.h"
#import "FLEXRuntimeUtility.h"
#import "FLEXMetadataExtras.h"
#import "FLEXUtility.h"
#import "FLEXColor.h"
#import "UIBarButtonItem+FLEX.h"
#import <objc/runtime.h>

@interface FLEXFieldEditorViewController () <FLEXArgumentInputViewDelegate>

@property (nonatomic, readonly) id<FLEXMetadataAuxiliaryInfo> auxiliaryInfoProvider;
@property (nonatomic) FLEXProperty *property;
@property (nonatomic) FLEXIvar *ivar;

@property (nonatomic, readonly) id currentValue;
@property (nonatomic, readonly) const FLEXTypeEncoding *typeEncoding;
@property (nonatomic, readonly) NSString *fieldDescription;

@end

@implementation FLEXFieldEditorViewController

#pragma mark - Initialization

+ (instancetype)target:(id)target property:(nonnull FLEXProperty *)property commitHandler:(void(^)(void))onCommit {
    FLEXFieldEditorViewController *editor = [self target:target data:property commitHandler:onCommit];
    editor.title = [@"Property: " stringByAppendingString:property.name];
    editor.property = property;
    return editor;
}

+ (instancetype)target:(id)target ivar:(nonnull FLEXIvar *)ivar commitHandler:(void(^)(void))onCommit {
    FLEXFieldEditorViewController *editor = [self target:target data:ivar commitHandler:onCommit];
    editor.title = [@"Ivar: " stringByAppendingString:ivar.name];
    editor.ivar = ivar;
    return editor;
}

#pragma mark - Overrides

- (void)viewDidLoad {
    [super viewDidLoad];

    // The superclass installs a translucent Liquid Glass background; keep the
    // field editor transparent so live changes remain visible underneath.
    self.view.backgroundColor = UIColor.clearColor;

    // Create getter button
    _getterButton = [[UIBarButtonItem alloc]
        initWithTitle:@"Get"
        style:UIBarButtonItemStyleDone
        target:self
        action:@selector(getterButtonPressed:)
    ];
    self.toolbarItems = @[
        UIBarButtonItem.flex_flexibleSpace, self.getterButton, self.actionButton
    ];
    
    [self registerAuxiliaryInfo];

    // Configure input view
    self.fieldEditorView.fieldDescription = self.fieldDescription;
    FLEXArgumentInputView *inputView = [FLEXArgumentInputViewFactory argumentInputViewForTypeEncoding:self.typeEncoding];
    inputView.inputValue = self.currentValue;
    inputView.delegate = self;

    // Offer a searchable pool of values for selector- and string-typed fields
    // so users don't have to type (or guess) the value by hand.
    if ([FLEXArgumentInputStringView isSelectorTypeEncoding:self.typeEncoding]) {
        BOOL isInstanceMethod = !object_isClass(self.target);
        inputView.suggestedValues = [FLEXArgumentInputStringView
            selectorNamesForObject:self.target
            instanceMethod:isInstanceMethod
        ];
        inputView.suggestedValuesTitle = @"Selectors";
    } else if ([FLEXArgumentInputStringView isStringObjectTypeEncoding:self.typeEncoding]) {
        // String fields get a fast pool of key paths and defaults keys up
        // front, plus a lazy scan of heap strings and runtime names.
        inputView.suggestedValuesTitle = @"Values";
        // Assign the loader first so the "Choose" button stays visible even
        // when the fast pool above is empty.
        inputView.suggestedValuesLoader = ^(void(^done)(NSArray<NSString *> *values)) {
            [FLEXArgumentInputStringView additionalStringsWithCompletion:done];
        };
        inputView.suggestedValues = [FLEXArgumentInputStringView
            suggestedStringsForObject:self.target
        ];
    }

    self.fieldEditorView.argumentInputViews = @[inputView];

    // Don't show a "set" button for switches; we mutate when the switch is flipped
    if ([inputView isKindOfClass:[FLEXArgumentInputSwitchView class]]) {
        self.actionButton.enabled = NO;
        self.actionButton.title = @"Flip the switch to call the setter";
        // Put getter button before setter button 
        self.toolbarItems = @[
            UIBarButtonItem.flex_flexibleSpace, self.actionButton, self.getterButton
        ];
    }
}

- (void)actionButtonPressed:(id)sender {
    if (self.property) {
        id userInputObject = self.firstInputView.inputValue;
        NSArray *arguments = userInputObject ? @[userInputObject] : nil;
        SEL setterSelector = self.property.likelySetter;
        NSError *error = nil;
        [FLEXRuntimeUtility performSelector:setterSelector onObject:self.target withArguments:arguments error:&error];
        if (error) {
            [FLEXAlert showAlert:@"Property Setter Failed" message:error.localizedDescription from:self];
            sender = nil; // Don't pop back
        }
    } else {
        // TODO: check mutability and use mutableCopy if necessary;
        // this currently could and would assign NSArray to NSMutableArray
        [self.ivar setValue:self.firstInputView.inputValue onObject:self.target];
    }
    
    // Dismiss keyboard and handle committed changes
    [super actionButtonPressed:sender];

    // Go back after setting, but not for switches.
    if (sender) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        self.firstInputView.inputValue = self.currentValue;
    }
}

- (void)getterButtonPressed:(id)sender {
    [self.fieldEditorView endEditing:YES];

    [self exploreObjectOrPopViewController:self.currentValue];
}

- (void)argumentInputViewValueDidChange:(FLEXArgumentInputView *)argumentInputView {
    if ([argumentInputView isKindOfClass:[FLEXArgumentInputSwitchView class]]) {
        [self actionButtonPressed:nil];
    }
}

#pragma mark - Private

- (void)registerAuxiliaryInfo {
    // This is how Reflex will get Swift struct field names into the editor at runtime
    NSDictionary<NSString *, NSArray *> *labels = [self.auxiliaryInfoProvider
        auxiliaryInfoForKey:FLEXAuxiliarynfoKeyFieldLabels
    ];
    
    for (NSString *type in labels) {
        [FLEXArgumentInputViewFactory registerFieldNames:labels[type] forTypeEncoding:type];
    }
}

- (id)currentValue {
    if (self.property) {
        return [self.property getValue:self.target];
    } else {
        return [self.ivar getValue:self.target];
    }
}

- (id<FLEXMetadataAuxiliaryInfo>)auxiliaryInfoProvider {
    return self.ivar ?: self.property;
}

- (const FLEXTypeEncoding *)typeEncoding {
    if (self.property) {
        return self.property.attributes.typeEncoding.UTF8String;
    } else {
        return self.ivar.typeEncoding.UTF8String;
    }
}

- (NSString *)fieldDescription {
    if (self.property) {
        return self.property.fullDescription;
    } else {
        return self.ivar.description;
    }
}

@end
