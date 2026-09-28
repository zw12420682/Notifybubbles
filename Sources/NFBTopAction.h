#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>
// Unknown, mini and transitioning windows must never receive this action.
static inline NSInteger NFBExpandedWindowKind(NSInteger mini, NSInteger transitioning,
        NSInteger scene, NSInteger container) {
    if (mini != 0 || transitioning != 0 || scene < 1 || scene > 4 || container < 1 || container > 4) return 0;
    return (scene >= 3 || container >= 3) ? 2 : 1;
}
// Known TrollOpen 1.5.2 title-bar long-press handler. No private gesture pointers.
static inline BOOL NFBDispatchTopLongPress(id target, id gesture) {
    if (!target || !gesture) return NO;
    @try {
        SEL action = NSSelectorFromString(@"TOJBMETHOD087:");
        if (![target respondsToSelector:action]) return NO;
        NSMethodSignature *sig = [target methodSignatureForSelector:action];
        if (sig.numberOfArguments != 3 || strcmp(sig.methodReturnType, @encode(void)) ||
            strcmp([sig getArgumentTypeAtIndex:2], @encode(id))) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(target, action, gesture);
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
