#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>
// 1.5.2 single-tap handler verified in the supplied binary. Register its known
// name with the runtime; never read a selector from gesture private storage.
static inline BOOL NFBDispatchRightEdgeTap(id target, id tap) {
    if (!target || !tap) return NO;
    @try {
        SEL action = NSSelectorFromString(@"TOJBMETHOD063:");
        if (![target respondsToSelector:action]) return NO;
        NSMethodSignature *sig = [target methodSignatureForSelector:action];
        if (sig.numberOfArguments != 3 || strcmp(sig.methodReturnType, @encode(void)) ||
            strcmp([sig getArgumentTypeAtIndex:2], @encode(id))) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(target, action, tap);
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
