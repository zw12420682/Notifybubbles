#import "NFBSystemDesktop.h"
#import "NFBExitInvocation.h"
#import "NFBAppExit.h"
#import "NFBDebugLog.h"
#import "NFBPrivate.h"
#import <objc/message.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/types.h>
#include <limits.h>

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
        NFBErrorLog(@"exit: SBApplicationController unavailable");
        return nil;
    }
    @try {
        NSMethodSignature *sig = NFBSignature(controller, selector);
        if (!sig || sig.numberOfArguments != 3 || sig.methodReturnType[0] != '@' || [sig getArgumentTypeAtIndex:2][0] != '@') return nil;
        return ((id (*)(id, SEL, id))objc_msgSend)(controller, selector, bundleID);
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"exit: application lookup threw %@", error);
        return nil;
    }
}

// Fill whichever trailing arguments the discovered selector declares. Signatures
// differ (`forReason:`, `andReport:`, `withDescription:` come and go between
// releases), so each slot is filled by its declared type rather than by position.
// Primary path: FBSystemService owns real terminations, so the app is torn down
// with the same bookkeeping the switcher uses (state saved, card animated out).
static BOOL NFBTerminateViaSystemService(id process) {
    Class serviceClass = NSClassFromString(@"FBSystemService");
    id service = NFBGet(serviceClass, @"sharedService") ?: NFBSingleton(@"FBSystemService");
    if (!service) {
        NFBErrorLog(@"exit: FBSystemService unavailable");
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
    static NFBBackBoardTerminate cached;
    static void *framework;
    NFBBackBoardTerminate terminate = cached ?: (NFBBackBoardTerminate)dlsym(RTLD_DEFAULT,
        "BKSTerminateApplicationForReasonAndReportWithDescription");
    if (!terminate) {
        if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
        if (framework) terminate = (NFBBackBoardTerminate)dlsym(framework, "BKSTerminateApplicationForReasonAndReportWithDescription");
    }
    if (!terminate) {
        NFBDebugLog(@"exit: BKSTerminateApplication... unresolved");
        return NO;
    }
    cached = terminate;
    @try {
        BOOL accepted = terminate(bundleID, NFBExitReasonUser, NO, @"NotifyBubbles exit");
        NFBDebugLog(@"exit: BKSTerminate -> %d", accepted);
        return accepted;
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"exit: BKSTerminate threw %@", error);
        return NO;
    }
}

// Last resort: signal the process directly. Only reached when both service
// paths are missing, and deliberately mirrors the switcher's SIGKILL.
static pid_t NFBPID(id application) {
    @try {
        SEL selector = NSSelectorFromString(@"pid");
        NSMethodSignature *signature = NFBSignature(application, selector);
        if (!signature || signature.numberOfArguments != 2) return 0;
        NSInteger value = 0;
        char type = signature.methodReturnType[0];
        if (type == 'i') value = ((int (*)(id, SEL))objc_msgSend)(application, selector);
        else if (type == 'q' || type == 'l') value = ((NSInteger (*)(id, SEL))objc_msgSend)(application, selector);
        else return 0;
        return value > 1 && value <= INT_MAX ? (pid_t)value : 0;
    } @catch (__unused NSException *error) { return 0; }
}
NSInteger NFBRunningProcessID(NSString *bundleID) {
    if (NFBIsSystemDesktop(bundleID)) return 0;
    if (!NSThread.isMainThread) return 0;
    // Verified iOS 16 service lookup; SBApplication.pid is absent on some builds.
    id service = NFBGet(NSClassFromString(@"FBSSystemService"), @"sharedService");
    SEL sel = NSSelectorFromString(@"pidForApplication:");
    NSMethodSignature *sig = NFBSignature(service, sel);
    if (sig && sig.numberOfArguments == 3 && [sig getArgumentTypeAtIndex:2][0] == '@' &&
        strcmp(sig.methodReturnType, @encode(int)) == 0) {
        @try {
            int pid = ((int (*)(id, SEL, id))objc_msgSend)(service, sel, bundleID);
            if (pid > 1) return pid;
        } @catch (__unused NSException *error) {}
    }
    id application = NFBApplicationForBundle(bundleID);
    pid_t pid = NFBPID(application);
    if (pid <= 1) pid = NFBPID(NFBGet(application, @"process"));
    return pid;
}
static BOOL NFBTerminateBySignal(id application) {
    pid_t pid = NFBPID(application);
    if (pid <= 1) return NO;
    int result = kill(pid, SIGKILL);
    NFBDebugLog(@"exit: kill(%d) -> %d", pid, result);
    return result == 0;
}

BOOL NFBTerminateApp(NSString *bundleID) {
    if (NFBIsSystemDesktop(bundleID)) return NO;
    if (!NSThread.isMainThread) return NO;
    if (![bundleID isKindOfClass:NSString.class] || !bundleID.length) return NO;
    @try {
        // iOS 16's public private-service header names FBSSystemService. Unlike
        // the legacy FBSystemService path it accepts a bundle ID, not a process.
        Class fbsClass = NSClassFromString(@"FBSSystemService");
        id fbsService = NFBGet(fbsClass, @"sharedService") ?: NFBSingleton(@"FBSSystemService");
        if (NFBInvokeBundleTerminate(fbsService, bundleID)) {
            NFBDebugLog(@"exit: FBSSystemService request sent %@ (completion unknown)", bundleID);
            return YES;
        }
        id application = NFBApplicationForBundle(bundleID);
        if (!application) {
            if (NFBTerminateViaBackBoard(bundleID)) return YES;
            NFBDebugLog(@"exit: no SBApplication for %@", bundleID);
            return NO;
        }
        id process = NFBGet(application, @"process") ?: application;
        NFBDebugLog(@"exit: app=%@ process=%@", NSStringFromClass([application class]),
                    NSStringFromClass([process class]));
        if (NFBTerminateViaSystemService(process)) return YES;
        if (NFBTerminateViaBackBoard(bundleID)) return YES;
        if (NFBTerminateBySignal(application)) return YES;
        NFBErrorLog(@"exit: no working termination path for %@", bundleID);
        return NO;
    } @catch (NSException *error) {
        NFBErrorLog(@"exit: failed for %@: %@", bundleID, error);
        return NO;
    }
}

BOOL NFBTerminateSurvivingProcess(NSString *bundleID, NSInteger capturedPID) {
    if (!NSThread.isMainThread || NFBIsSystemDesktop(bundleID) || capturedPID <= 1) return NO;
    id application = NFBApplicationForBundle(bundleID);
    NSInteger currentPID = NFBRunningProcessID(bundleID);
    if (currentPID != capturedPID || currentPID <= 1 || currentPID > INT_MAX) return NO;
    (void)application;
    int result = kill((pid_t)currentPID, SIGKILL);
    NFBDebugLog(@"exit: verified same-pid kill %ld -> %d", (long)currentPID, result);
    return result == 0;
}
