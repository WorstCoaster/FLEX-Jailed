//
//  FLEXArgumentInputStringView.m
//  Flipboard
//
//  Created by Ryan Olson on 6/28/14.
//  Copyright (c) 2020 FLEX Team. All rights reserved.
//

#import "FLEXArgumentInputStringView.h"
#import "FLEXRuntimeUtility.h"
#import "FLEXHeapEnumerator.h"
#import <objc/runtime.h>

@implementation FLEXArgumentInputStringView

- (instancetype)initWithArgumentTypeEncoding:(const char *)typeEncoding {
    self = [super initWithArgumentTypeEncoding:typeEncoding];
    if (self) {
        FLEXTypeEncoding type = typeEncoding[0];
        if (type == FLEXTypeEncodingConst) {
            // A crash here would mean an invalid type encoding string
            type = typeEncoding[1];
        }

        // Selectors don't need a multi-line text box
        if (type == FLEXTypeEncodingSelector) {
            self.targetSize = FLEXArgumentInputViewSizeSmall;
        } else {
            self.targetSize = FLEXArgumentInputViewSizeLarge;
        }
    }
    return self;
}

- (void)setInputValue:(id)inputValue {
    if ([inputValue isKindOfClass:[NSString class]]) {
        self.inputTextView.text = inputValue;
    } else if ([inputValue isKindOfClass:[NSValue class]]) {
        NSValue *value = (id)inputValue;
        NSParameterAssert(strlen(value.objCType) == 1);

        // C-String or SEL from NSValue
        FLEXTypeEncoding type = value.objCType[0];
        if (type == FLEXTypeEncodingConst) {
            // A crash here would mean an invalid type encoding string
            type = value.objCType[1];
        }

        if (type == FLEXTypeEncodingCString) {
            self.inputTextView.text = @((const char *)value.pointerValue);
        } else if (type == FLEXTypeEncodingSelector) {
            self.inputTextView.text = NSStringFromSelector((SEL)value.pointerValue);
        }
    }
}

- (id)inputValue {
    NSString *text = self.inputTextView.text;
    // Interpret empty string as nil. We loose the ability to set empty string as a string value,
    // but we accept that tradeoff in exchange for not having to type quotes for every string.
    if (!text.length) {
        return nil;
    }

    // Case: C-strings and SELs
    if (self.typeEncoding.length <= 2) {
        FLEXTypeEncoding type = [self.typeEncoding characterAtIndex:0];
        if (type == FLEXTypeEncodingConst) {
            // A crash here would mean an invalid type encoding string
            type = [self.typeEncoding characterAtIndex:1];
        }

        if (type == FLEXTypeEncodingCString || type == FLEXTypeEncodingSelector) {
            const char *encoding = self.typeEncoding.UTF8String;
            SEL selector = NSSelectorFromString(text);
            return [NSValue valueWithBytes:&selector objCType:encoding];
        }
    }

    // Case: NSStrings
    return self.inputTextView.text.copy;
}

// TODO: Support using object address for strings, as in the object arg view.

+ (BOOL)isSelectorTypeEncoding:(const char *)typeEncoding {
    if (typeEncoding == NULL) {
        return NO;
    }
    if (typeEncoding[0] == FLEXTypeEncodingSelector) {
        return YES;
    }
    return typeEncoding[0] == FLEXTypeEncodingConst && typeEncoding[1] == FLEXTypeEncodingSelector;
}

+ (BOOL)isStringObjectTypeEncoding:(const char *)typeEncoding {
    return typeEncoding != NULL && strcmp(typeEncoding, FLEXEncodeClass(NSString)) == 0;
}

+ (NSArray<NSString *> *)suggestedStringsForObject:(id)object {
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet new];

    // 1. KVC key paths available on the target, from the full class hierarchy.
    if (object) {
        Class cursor = object_isClass(object) ? (Class)object : object_getClass(object);
        while (cursor != NULL) {
            unsigned int count = 0;

            objc_property_t *properties = class_copyPropertyList(cursor, &count);
            for (unsigned int i = 0; i < count; i++) {
                const char *name = property_getName(properties[i]);
                if (name != NULL) {
                    [values addObject:@(name)];
                }
            }
            if (properties != NULL) {
                free(properties);
            }

            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList(cursor, &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                const char *name = ivar_getName(ivars[i]);
                if (name != NULL) {
                    NSString *ivarName = @(name);
                    // KVC strips the leading underscore from ivar-backed keys.
                    if ([ivarName hasPrefix:@"_"]) {
                        ivarName = [ivarName substringFromIndex:1];
                    }
                    [values addObject:ivarName];
                }
            }
            if (ivars != NULL) {
                free(ivars);
            }

            cursor = class_getSuperclass(cursor);
        }
    }

    // 2. Keys currently stored in user defaults, both global and app-specific.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [values addObjectsFromArray:defaults.dictionaryRepresentation.allKeys];
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (bundleID.length > 0) {
        [values addObjectsFromArray:[defaults persistentDomainForName:bundleID].allKeys];
    }

    return [[values array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (void)additionalStringsWithCompletion:(void(^)(NSArray<NSString *> *values))completion {
    if (!completion) {
        return;
    }

    // Heap enumeration walks a process-global, non-thread-safe class registry,
    // so keep the scan on the main queue like FLEX's other heap walkers. The
    // picker shows a spinner before this deferred work runs, so the brief pause
    // during the walk is expected rather than a hang.
    dispatch_async(dispatch_get_main_queue(), ^{
        completion([self collectAdditionalStrings]);
    });
}

/// Dynamically discovers string candidates that are relevant to the running
/// process, rather than relying on a hardcoded list.
+ (NSArray<NSString *> *)collectAdditionalStrings {
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet new];

    // Live NSString instances (and subclasses) on the heap.
    [self addHeapStringsToSet:values];
    // Class and protocol names registered with the Objective-C runtime.
    [self addRuntimeNamesToSet:values];

    return [[values array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (void)addHeapStringsToSet:(NSMutableOrderedSet<NSString *> *)values {
    static const NSUInteger kMaxHeapStrings = 2000;
    static const NSUInteger kMaxStringLength = 512;
    __block NSUInteger collected = 0;

    [FLEXHeapEnumerator enumerateLiveObjectsUsingBlock:^(
        __unsafe_unretained id object, __unsafe_unretained Class actualClass
    ) {
        if (collected >= kMaxHeapStrings) {
            return;
        }

        // Only touch objects whose isa chain leads to NSString, and never
        // message a candidate until we've retained it.
        if (![self class:actualClass isKindOfString]) {
            return;
        }

        id string = object;
        @try {
            if (string.length > 0) {
                if (string.length > kMaxStringLength) {
                    string = [string substringToIndex:kMaxStringLength];
                }
                [values addObject:string];
                collected++;
            }
        } @catch (NSException *exception) {
            // Ignore candidates that fail to produce a usable string.
            (void)exception;
        }
    }];
}

+ (BOOL)class:(Class)cls isKindOfString {
    static Class stringClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stringClass = [NSString class];
    });

    Class cursor = cls;
    while (cursor != NULL) {
        if (cursor == stringClass) {
            return YES;
        }
        cursor = class_getSuperclass(cursor);
    }
    return NO;
}

+ (void)addRuntimeNamesToSet:(NSMutableOrderedSet<NSString *> *)values {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount > 0) {
        Class *classes = (Class *)malloc((size_t)classCount * sizeof(Class));
        int actual = objc_getClassList(classes, classCount);
        for (int i = 0; i < actual; i++) {
            const char *name = class_getName(classes[i]);
            if (name != NULL) {
                [values addObject:@(name)];
            }
        }
        free(classes);
    }

    unsigned int protocolCount = 0;
    Protocol *__unsafe_unretained *protocols = objc_copyProtocolList(&protocolCount);
    for (unsigned int i = 0; i < protocolCount; i++) {
        const char *name = protocol_getName(protocols[i]);
        if (name != NULL) {
            [values addObject:@(name)];
        }
    }
    if (protocols != NULL) {
        free(protocols);
    }
}

+ (NSArray<NSString *> *)selectorNamesForObject:(id)object instanceMethod:(BOOL)instanceMethod {
    if (!object) {
        return @[];
    }

    Class cursor;
    if (instanceMethod) {
        // Instance methods live on the class and its superclass chain.
        cursor = object_isClass(object) ? (Class)object : object_getClass(object);
    } else {
        // Class methods live on the metaclass chain.
        Class metaclass = object_isClass(object) ?
            object_getClass((Class)object) :
            object_getClass(object_getClass(object));
        cursor = metaclass;
    }

    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet new];
    while (cursor) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        for (unsigned int i = 0; i < count; i++) {
            [names addObject:NSStringFromSelector(method_getName(methods[i]))];
        }
        if (methods) {
            free(methods);
        }
        cursor = class_getSuperclass(cursor);
    }

    return [[names array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (BOOL)supportsObjCType:(const char *)type withCurrentValue:(id)value {
    NSParameterAssert(type);
    unsigned long len = strlen(type);

    BOOL isConst = type[0] == FLEXTypeEncodingConst;
    NSInteger i = isConst ? 1 : 0;

    BOOL typeIsString = strcmp(type, FLEXEncodeClass(NSString)) == 0;
    BOOL typeIsCString = len <= 2 && type[i] == FLEXTypeEncodingCString;
    BOOL typeIsSEL = len <= 2 && type[i] == FLEXTypeEncodingSelector;
    BOOL valueIsString = [value isKindOfClass:[NSString class]];

    BOOL typeIsPrimitiveString = typeIsSEL || typeIsCString;
    BOOL typeIsSupported = typeIsString || typeIsCString || typeIsSEL;

    BOOL valueIsNSValueWithCorrectType = NO;
    if ([value isKindOfClass:[NSValue class]]) {
        NSValue *v = (id)value;
        len = strlen(v.objCType);
        if (len == 1) {
            FLEXTypeEncoding type = v.objCType[i];
            if (type == FLEXTypeEncodingCString && typeIsCString) {
                valueIsNSValueWithCorrectType = YES;
            } else if (type == FLEXTypeEncodingSelector && typeIsSEL) {
                valueIsNSValueWithCorrectType = YES;
            }
        }
    }

    if (!value && typeIsSupported) {
        return YES;
    }

    if (typeIsString && valueIsString) {
        return YES;
    }

    // Primitive strings can be input as NSStrings or NSValues
    if (typeIsPrimitiveString && (valueIsString || valueIsNSValueWithCorrectType)) {
        return YES;
    }

    return NO;
}

@end
