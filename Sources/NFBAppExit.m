#import "NFBAppExit.h"
#import "NFBDebugLog.h"
#import "NFBPrivate.h"
#import <objc/message.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/types.h>

// Quit an app the way the App Switcher's swipe-up card does: hand the process to
// SpringBoard's own lifecycle service instead of just suspending it. The private
// entry points differ between iOS generations, so each candidate is probed at
// runtime and the first one that answers wins — a missing symbol on one firmware
// never leaves the gesture dead.

// 1 = user-initiated exit (what the switcher reports). report=NO keeps the exit
// out of the crash reporter, exactly like a real swipe-up.
static const NSInteger NFBExitReasonUser = 1;

// Look the app object up through SpringBoard's own application registry.
static id NFBApplicationForBundle(NSString *bundleID) {
    if (![bundleID isKindOfClass:NSString.class] || !bundleID.length) return nil;
    id controller = NFBSingleton(@"SBApplicationController");
    SEL selector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (![controller respondsToSelector:selector]) {
        NFBDebugLog(@"exit: SBApplicationController unavailable");
        return nil;
    }
    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleID);
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"exit: application lookup threw %@", error);
        return nil;
    }
}

// Fill whichever trailing arguments the discovered selector declares. Signatures
// differ (`forReason:`, `andReport:`, `withDescription:` come and go between
// releases), so each slot is filled by its declared type rather than by position.
static BOOL NFBInvokeTerminate(id service, SEL selector, id process) {
    if (!service || !process || ![service respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [service methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments < 3) return NO;
    if ([signature getArgumentTypeAtIndex:2][0] != '@') return NO;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    __unsafe_unretained id argument = process;
    [invocation setArgument:&argument atIndex:2];
    NSInteger reason = NFBExitReasonUser;
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
        NFBDebugLog(@"exit: invoked -[%@ %@]", NSStringFromClass([service class]), NSStringFromSelector(selector));
        return YES;
    } @catch (NSException *error) {
        NFBDebugLog(@"exit: %@ threw %@", NSStringFromSelector(selector), error);
        return NO;
    }
}

// Primary path: FBSystemService owns real terminations, so the app is torn down
// with the same bookkeeping the switcher uses (state saved, card animated out).
static BOOL NFBTerminateViaSystemService(id process) {
    Class serviceClass = NSClassFromString(@"FBSystemService");
    id service = NFBGet(serviceClass, @"sharedService") ?: NFBSingleton(@"FBSystemService");
    if (!service) {
        NFBDebugLog(@"exit: FBSystemService unavailable");
        return NO;
    }
    NSArray<NSString *> *selectors = @[@"terminateApplication:forReason:andReport:withDescription:",
                                       @"terminateApplication:forReason:andReport:",
                                       @"terminateApplication:forReason:",
                                       @"terminateApplication:"];
    for (NSString *name in selectors) {
        if (NFBInvokeTerminate(service, NSSelectorFromString(name), process)) return YES;
    }
    return NO;
}

typedef BOOL (*NFBBackBoardTerminate)(NSString *, NSInteger, BOOL, NSString *);

// Fallback path: the BackBoardServices C function, present on every recent
// firmware and still accepted by SpringBoard's process manager.
static BOOL NFBTerminateViaBackBoard(NSString *bundleID) {
    NFBBackBoardTerminate terminate = (NFBBackBoardTerminate)dlsym(RTLD_DEFAULT,
        "BKSTerminateApplicationForReasonAndReportWithDescription");
    if (!terminate) {
        void *handle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        if (handle) terminate = (NFBBackBoardTerminate)dlsym(handle, "BKSTerminateApplicationForReasonAndReportWithDescription");
    }
    if (!terminate) {
        NFBDebugLog(@"exit: BKSTerminateApplication... unresolved");
        return NO;
    }
    @try {
        BOOL accepted = terminate(bundleID, NFBExitReasonUser, NO, @"NotifyBubbles exit");
        NFBDebugLog(@"exit: BKSTerminate -> %d", accepted);
        return accepted;
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"exit: BKSTerminate threw %@", error);
        return NO;
    }
}

// Last resort: signal the process directly. Only reached when both service
// paths are missing, and deliberately mirrors the switcher's SIGKILL.
static BOOL NFBTerminateBySignal(id application) {
    SEL selector = NSSelectorFromString(@"pid");
    if (![application respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [application methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;
    pid_t pid = 0;
    char type = signature.methodReturnType[0];
    if (type == 'i') pid = (pid_t)((int (*)(id, SEL))objc_msgSend)(application, selector);
    else if (type == 'q' || type == 'l') pid = (pid_t)((NSInteger (*)(id, SEL))objc_msgSend)(application, selector);
    else return NO;
    if (pid <= 1) return NO;
    int result = kill(pid, SIGKILL);
    NFBDebugLog(@"exit: kill(%d) -> %d", pid, result);
    return result == 0;
}

BOOL NFBTerminateApp(NSString *bundleID) {
    if (!NSThread.isMainThread) return NO;
    if (![bundleID isKindOfClass:NSString.class] || !bundleID.length) return NO;
    @try {
        id application = NFBApplicationForBundle(bundleID);
        if (!application) {
            NFBDebugLog(@"exit: no SBApplication for %@", bundleID);
            return NO;
        }
        id process = NFBGet(application, @"process") ?: application;
        NFBDebugLog(@"exit: app=%@ process=%@", NSStringFromClass([application class]),
                    NSStringFromClass([process class]));
        if (NFBTerminateViaSystemService(process)) return YES;
        if (NFBTerminateViaBackBoard(bundleID)) return YES;
        if (NFBTerminateBySignal(application)) return YES;
        NFBDebugLog(@"exit: no working termination path for %@", bundleID);
        return NO;
    } @catch (NSException *error) {
        NFBDebugLog(@"exit: failed for %@: %@", bundleID, error);
        return NO;
    }
}
