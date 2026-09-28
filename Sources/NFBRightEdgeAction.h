#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>
// 1.5.2 single-tap handler. Only use after confirming its real binding on
// rightTouchRegion. Its body reads recognizer.state, then calls TOJBMETHOD256.
static inline BOOL NFBDispatchRightEdgeTap(id target, SEL action, id tap) {
    if (!tap || ![NSStringFromSelector(action) isEqualToString:@"TOJBMETHOD063:"] ||
        ![target respondsToSelector:action]) return NO;
    @try {
        NSMethodSignature *sig = [target methodSignatureForSelector:action];
        if (sig.numberOfArguments != 3 || strcmp(sig.methodReturnType, @encode(void)) ||
            strcmp([sig getArgumentTypeAtIndex:2], @encode(id))) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(target, action, tap);
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
