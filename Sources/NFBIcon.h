#pragma once
#import <UIKit/UIKit.h>
#import "NFBInterfaces.h"
static inline UIImage *NFBApplicationImage(NSString *app, int format, CGFloat scale) {
    if (!app.length) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 128; });
    NSString *key = [NSString stringWithFormat:@"%@|%d|%.2f", app, format, scale];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    @try {
        NSMethodSignature *sig = NFBSignature(UIImage.class, selector);
        if (!sig || sig.numberOfArguments != 5 || sig.methodReturnType[0] != '@' ||
            [sig getArgumentTypeAtIndex:2][0] != '@' ||
            strcmp([sig getArgumentTypeAtIndex:4], @encode(CGFloat))) return nil;
        char formatType = [sig getArgumentTypeAtIndex:3][0];
        if (formatType == 'i') image = ((id (*)(id, SEL, id, int, CGFloat))objc_msgSend)(UIImage.class, selector, app, format, scale);
        else if (formatType == 'q') image = ((id (*)(id, SEL, id, NSInteger, CGFloat))objc_msgSend)(UIImage.class, selector, app, format, scale);
        if (![image isKindOfClass:UIImage.class]) return nil;
        [cache setObject:image forKey:key];
        return image;
    } @catch (__unused NSException *error) { return nil; }
}
