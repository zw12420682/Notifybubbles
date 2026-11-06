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


// FBSSystemService on iOS 16 takes an application bundle identifier, not an
// FBProcess/SBApplication object. Keep this explicit and test the actual argument.
static inline BOOL NFBInvokeBundleTerminate(id service, NSString *bundleID) {
    if (![bundleID isKindOfClass:NSString.class] || !bundleID.length) return NO;
    return NFBInvokeTerminate(service,
        NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:"), bundleID);
}

// Native switcher swipe-away path, documented in the open-source QuitAll tweak.
// Never call an ABI-guessed method: layout object + signed integer reason only.
static inline BOOL NFBInvokeQuitLayout(id controller, id layout) {
    SEL sel = NSSelectorFromString(@"_quitAppsRepresentedByAppLayout:forReason:");
    if (!controller || !layout || ![controller respondsToSelector:sel]) return NO;
    NSMethodSignature *sig = NFBSignature(controller, sel);
    if (!sig || sig.numberOfArguments != 4 || strcmp(sig.methodReturnType, @encode(void)) ||
        [sig getArgumentTypeAtIndex:2][0] != '@') return NO;
    const char *t = [sig getArgumentTypeAtIndex:3];
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:sig];
    call.selector = sel;
    __unsafe_unretained id value = layout;
    [call setArgument:&value atIndex:2];
    if (t[0] == 'q' || t[0] == 'l') {
        NSInteger reason = 1; [call setArgument:&reason atIndex:3];
    } else if (t[0] == 'i') {
        int reason = 1; [call setArgument:&reason atIndex:3];
    } else return NO;
    @try { [call invokeWithTarget:controller]; return YES; }
    @catch (NSException *error) { NFBErrorLog(@"switcher quit threw %@", error); return NO; }
}
