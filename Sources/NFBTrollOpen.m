#import <TargetConditionals.h>
// macOS contract tests always use the Foundation-only adapter, even when an
// older workflow omits the test macro. iOS keeps the shared UIKit snapshot.
#if TARGET_OS_OSX && !defined(NFB_PORTABLE_ADAPTER_TEST)
#define NFB_PORTABLE_ADAPTER_TEST 1
#endif
#import "NFBTrollOpen.h"
#ifdef NFB_PORTABLE_ADAPTER_TEST
// Contract tests also work with the original Foundation-only compile command.
// Production logging remains in NFBDebugLog.m on iOS.
#include <stdarg.h>
static void NFBAdapterDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void NFBAdapterDebugLog(__unused NSString *format, ...) {}
static void NFBAdapterErrorLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void NFBAdapterErrorLog(NSString *format, ...) {
    va_list arguments; va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[NFB adapter test] %@", message);
}
#define NFBDebugLog NFBAdapterDebugLog
#define NFBErrorLog NFBAdapterErrorLog
#else
#import "NFBDebugLog.h"
#endif
#import "NFBInterfaces.h"
#ifndef NFB_PORTABLE_ADAPTER_TEST
#import "NFBWindowState.h"
#endif
static void NFBTrollDidMutate(void) {
#ifndef NFB_PORTABLE_ADAPTER_TEST
    NFBInvalidateWindowState();
#endif
}
#import <objc/message.h>
#include <string.h>

// Forward declaration: fetches an object-returning no-argument method result.
static id NFBTrollObject(id object, NSString *name);

// The TrollOpen selector set is not fully documented: the official 1.3.7 build
// and the 1.3.7 custom build differ, and control actions such as
// closeCurrentFloatingWindow live on the BRIDGE CLASS, not on the floating window
// instance. Dump the methods containing control-related keywords exactly once so
// the debug file reveals the correct selector names instead of us guessing again.
static void NFBDumpFloatingWindowInterfaces(__unused id window) {
#ifndef NFB_PORTABLE_ADAPTER_TEST
    static BOOL dumped = NO;
    if (dumped) return;
    dumped = YES;
    NFBDumpMethods(window, NO, @"floating", @[@"close", @"float", @"mini", @"full", @"hide", @"dismiss",
                                             @"remove", @"orientation", @"rotate", @"landscape",
                                             @"container", @"window", @"mode"]);
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    NFBDumpMethods(bridge, YES, @"bridge", @[@"floating", @"split", @"close", @"full", @"mini",
                                             @"orientation", @"gesture", @"current", @"visible"]);
#endif
}

BOOL NFBSplitTrollFrontmostApp(void) {
    if (!NSThread.isMainThread) return NO;
    // RootHide TrollOpen 1.3.7: +[TOJBBarGestureBridge splitFrontmostApplication], v16@0:8.
    // Let the plugin own the fullscreen-to-floating transition, rather than
    // pulling the foreground scene through its generic bundle-ID entry point.
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    SEL selector = NSSelectorFromString(@"splitFrontmostApplication");
    @try {
        if (![bridge respondsToSelector:selector]) return NO;
        NSMethodSignature *sig = NFBSignature(bridge, selector);
        if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void)) != 0) return NO;
        ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
#ifndef NFB_PORTABLE_ADAPTER_TEST
        NFBInvalidateWindowState();
#endif
        return YES;
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"TrollOpen foreground split failed: %@", error);
        return NO;
    }
}

// Close the current floating window. The device-side method dump proved
// closeCurrentFloatingWindow is a CLASS method on TOJBBarGestureBridge
// (B16@0:8 on the metaclass), NOT an instance method on the floating window —
// which is why the earlier instance-based lookup always reported "unavailable".
BOOL NFBCloseCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        // Diagnostics run once per SpringBoard launch: the floating window's
        // real selector set is build-specific, and the file is the only way to
        // confirm a future TrollOpen update did not rename the control methods.
        NFBDumpFloatingWindowInterfaces(NFBTrollObject(bridge, @"currentVisibleFloatingWindow"));
        SEL selector = NSSelectorFromString(@"closeCurrentFloatingWindow");
        if (bridge && [bridge respondsToSelector:selector]) {
            NSMethodSignature *sig = NFBSignature(bridge, selector);
            char ret = sig ? sig.methodReturnType[0] : '?';
            if (sig && sig.numberOfArguments == 2 && (ret == 'v' || ret == 'B' || ret == 'c')) {
                BOOL accepted = ret == 'v' ? YES : ((BOOL (*)(id, SEL))objc_msgSend)(bridge, selector);
                if (ret == 'v') ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
                if (!accepted) return NO;
                NFBDebugLog(@"close: invoked +[TOJBBarGestureBridge closeCurrentFloatingWindow]");
                NFBTrollDidMutate(); return YES;
            }
            NFBErrorLog(@"close: class method signature mismatch ret=%c args=%lu", ret,
                        sig ? (unsigned long)sig.numberOfArguments : 0);
        } else {
            NFBDebugLog(@"close: +[TOJBBarGestureBridge closeCurrentFloatingWindow] not available");
        }
        // Fallback: the floating window instance exposes process-closing helpers
        // (also confirmed present in the device-side dump, both void with no args).
        id window = NFBTrollObject(bridge, @"currentVisibleFloatingWindow");
        for (NSString *name in @[@"closeWindowWithoutTerminatingProcessImmediately",
                                 @"closeWindowWithoutTerminatingProcessWithoutAnimation"]) {
            SEL sel = NSSelectorFromString(name);
            if (![window respondsToSelector:sel]) continue;
            NSMethodSignature *sig = NFBSignature(window, sel);
            if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != 'v') continue;
            ((void (*)(id, SEL))objc_msgSend)(window, sel);
            NFBDebugLog(@"close: invoked -%@ (fallback)", name);
            NFBTrollDidMutate(); return YES;
        }
        NFBDebugLog(@"close: no usable close path");
        return NO;
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"TrollOpen close failed: %@", error);
        return NO;
    }
}

// Accept only a no-argument call that returns void or BOOL; anything else could
// be a same-named helper with a different contract.
static BOOL NFBCallSimple(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) return NO;
    NSMethodSignature *sig = NFBSignature(target, selector);
    if (!sig || sig.numberOfArguments != 2) return NO;
    char ret = sig.methodReturnType[0];
    if (ret != 'v' && ret != 'B' && ret != 'c') return NO;
    if (ret == 'v') { ((void (*)(id, SEL))objc_msgSend)(target, selector); NFBTrollDidMutate(); return YES; }
    BOOL accepted = ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
    if (accepted) NFBTrollDidMutate();
    return accepted;
}

BOOL NFBFullscreenCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        // The device-side dump lists it on the bridge metaclass, while an earlier
        // build carried it as an instance method on the floating window. Probe the
        // class method first and fall back, so neither layout can fail here.
        SEL selector = NSSelectorFromString(@"fullscreenCurrentFloatingWindow");
        if (NFBCallSimple(bridge, selector)) {
            NFBDebugLog(@"fullscreen: invoked +[TOJBBarGestureBridge fullscreenCurrentFloatingWindow]");
            NFBTrollDidMutate(); return YES;
        }
        id window = NFBTrollObject(bridge, @"currentVisibleFloatingWindow");
        NFBDumpFloatingWindowInterfaces(window);
        if (NFBCallSimple(window, selector)) {
            NFBDebugLog(@"fullscreen: invoked -[%@ fullscreenCurrentFloatingWindow]",
                        NSStringFromClass([window class]));
            NFBTrollDidMutate(); return YES;
        }
        NFBDebugLog(@"fullscreen: no usable path (bridge class=%d window=%d)",
                    bridge != nil, window != nil);
        return NO;
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"TrollOpen fullscreen failed: %@", error);
        return NO;
    }
}

// Shrink the current floating window to its mini size. The device-side method
// dump lists minimizeCurrentFloatingWindow on the bridge metaclass, but the
// owner of these control selectors has drifted across builds before, so probe
// the class method first and fall back to the window instance — the same
// dual-path shape fullscreen uses.
BOOL NFBMinimizeCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        SEL selector = NSSelectorFromString(@"minimizeCurrentFloatingWindow");
        if (NFBCallSimple(bridge, selector)) {
            NFBDebugLog(@"minimize: invoked +[TOJBBarGestureBridge minimizeCurrentFloatingWindow]");
            NFBTrollDidMutate(); return YES;
        }
        id window = NFBTrollObject(bridge, @"currentVisibleFloatingWindow");
        NFBDumpFloatingWindowInterfaces(window);
        if (NFBCallSimple(window, selector)) {
            NFBDebugLog(@"minimize: invoked -[%@ minimizeCurrentFloatingWindow]",
                        NSStringFromClass([window class]));
            NFBTrollDidMutate(); return YES;
        }
        // Some builds split the action into "shrink" rather than "minimize".
        SEL shrink = NSSelectorFromString(@"shrinkFloatingWindows");
        if (NFBCallSimple(bridge, shrink)) {
            NFBDebugLog(@"minimize: invoked +[TOJBBarGestureBridge shrinkFloatingWindows]");
            NFBTrollDidMutate(); return YES;
        }
        if (NFBCallSimple(window, shrink)) {
            NFBDebugLog(@"minimize: invoked -[%@ shrinkFloatingWindows]",
                        NSStringFromClass([window class]));
            NFBTrollDidMutate(); return YES;
        }
        NFBDebugLog(@"minimize: no usable path (bridge class=%d window=%d)",
                    bridge != nil, window != nil);
        return NO;
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"TrollOpen minimize failed: %@", error);
        return NO;
    }
}

static BOOL NFBTrollSignature(id target, SEL selector, BOOL hasFlag) {
    if (![target respondsToSelector:selector]) return NO;
    NSMethodSignature *sig = NFBSignature(target, selector);
    if (!sig || sig.numberOfArguments != (hasFlag ? 4u : 3u) ||
        strcmp(sig.methodReturnType, @encode(void)) != 0 ||
        [sig getArgumentTypeAtIndex:2][0] != '@') return NO;
    if (hasFlag) {
        char type = [sig getArgumentTypeAtIndex:3][0];
        if (type != 'B' && type != 'c') return NO;
    }
    return YES;
}

BOOL NFBOpenTrollApp(NSString *bundleID) {
    if (!NSThread.isMainThread || ![bundleID isKindOfClass:NSString.class] || !bundleID.length) return NO;
    // Verified against the supplied RootHide 1.3.7 binary's Objective-C metadata.
    // Its normal wrapper forwards to toj_showWithBundleID:skipOnlineLimitClose:
    // with NO. Call the wrapper, preserving TrollOpen's own behavior and checks.
    Class target = NSClassFromString(@"FloatingAppWindow");
    SEL open = NSSelectorFromString(@"showWithBundleID:");
    SEL fingerprint = NSSelectorFromString(@"toj_showWithBundleID:skipOnlineLimitClose:");
    @try {
        if (!NFBTrollSignature(target, open, NO) || !NFBTrollSignature(target, fingerprint, YES)) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(target, open, bundleID);
#ifndef NFB_PORTABLE_ADAPTER_TEST
        NFBInvalidateWindowState();
#endif
        return YES;
    } @catch (__unused NSException *error) {
        NFBErrorLog(@"TrollOpen open app failed: %@", error);
        return NO;
    }
}

static id NFBTrollObject(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    @try {
        NSMethodSignature *sig = NFBSignature(object, sel);
        if (![object respondsToSelector:sel] || !sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(object, sel);
    } @catch (__unused NSException *e) { return nil; }
}
NSString *NFBTrollVisibleApp(void) {
    if (!NSThread.isMainThread) return nil;
#ifdef NFB_PORTABLE_ADAPTER_TEST
    id window = NFBTrollObject(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
#else
    id window = NFBCurrentWindowState().floatingWindow;
#endif
    // Stop following the window as soon as its keep-alive close begins.
    SEL closing = NSSelectorFromString(@"isClosingWithKeepAliveAnimation");
    @try {
        NSMethodSignature *sig = NFBSignature(window, closing);
        if (sig.numberOfArguments == 2 && (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') &&
            ((BOOL (*)(id, SEL))objc_msgSend)(window, closing)) return nil;
    } @catch (__unused NSException *error) { return nil; }
    // A reduced mini-window is no longer the expanded split window.
    SEL mini = NSSelectorFromString(@"miniWindowModeEnabled");
    @try {
        NSMethodSignature *sig = NFBSignature(window, mini);
        if ([window respondsToSelector:mini] && sig.numberOfArguments == 2 &&
            (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') &&
            ((BOOL (*)(id, SEL))objc_msgSend)(window, mini)) return nil;
    } @catch (__unused NSException *e) { return nil; }
    id app = NFBTrollObject(window, @"bundleID");
    return [app isKindOfClass:NSString.class] ? app : nil;
}
