#pragma once
#import "NFBInterfaces.h"
#import "NFBDebugLog.h"
static inline BOOL NFBInvokeTerminate(id service, SEL selector, id process) {
    if (!service || !process || ![service respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = NFBSignature(service, selector);
    if (!signature || signature.numberOfArguments < 3) return NO;
    if ([signature getArgumentTypeAtIndex:2][0] != '@') return NO;
    char resultType = signature.methodReturnType[0];
    if (resultType != 'v' && resultType != 'B' && resultType != 'c') return NO;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    __unsafe_unretained id argument = process;
    [invocation setArgument:&argument atIndex:2];
    NSInteger reason = 1;
    BOOL report = NO;
    NSString *text = @"NotifyBubbles exit";
    for (NSUInteger index = 3; index < signature.numberOfArguments; index++) {
        char type = [signature getArgumentTypeAtIndex:index][0];
        if (type == 'q' || type == 'Q' || type == 'l' || type == 'L') {
            [invocation setArgument:&reason atIndex:index];
        } else if (type == 'i' || type == 'I') {
            int narrow = (int)reason;
            [invocation setArgument:&narrow atIndex:index];
        } else if (type == 'B' || type == 'c') {
            [invocation setArgument:&report atIndex:index];
        } else if (type == '@') {
            __unsafe_unretained id value = text;
            [invocation setArgument:&value atIndex:index];
        } else {
            NFBDebugLog(@"exit: %@ has unsupported argument %c", NSStringFromSelector(selector), type);
            return NO;
        }
    }
    @try {
        [invocation invokeWithTarget:service];
        if (resultType != 'v') {
            BOOL accepted = NO; [invocation getReturnValue:&accepted];
            if (!accepted) return NO;
        }
        NFBDebugLog(@"exit: invoked -[%@ %@]", NSStringFromClass([service class]), NSStringFromSelector(selector));
        return YES;
    } @catch (NSException *error) {
        NFBDebugLog(@"exit: %@ threw %@", NSStringFromSelector(selector), error);
        return NO;
    }
}

