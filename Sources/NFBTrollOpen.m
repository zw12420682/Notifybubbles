#import "NFBTrollOpen.h"
#import "NFBDebugLog.h"
#import <objc/message.h>
#include <string.h>

// Forward declaration: fetches an object-returning no-argument method result.
static id NFBTrollObject(id object, NSString *name);

// The floating-window object's real selector set is not fully documented: the
// official 1.3.7 build and the 1.5.2 custom build differ, and the device proved
// closeCurrentFloatingWindow is not callable on the 1.5.2 build in use. Dump the
// methods containing control-related keywords exactly once so the debug file
// reveals the correct selector names instead of us guessing again.
static void NFBDumpFloatingWindowInterfaces(id window) {
    static BOOL dumped = NO;
    if (dumped) return;
    dumped = YES;
    NFBDumpMethods(window, NO, @"floating", @[@"close", @"float", @"mini", @"full", @"hide", @"dismiss",
                                             @"remove", @"orientation", @"rotate", @"landscape",
                                             @"container", @"window", @"mode"]);
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    NFBDumpMethods(bridge, YES, @"bridge", @[@"floating", @"split", @"close", @"full", @"mini",
                                             @"orientation", @"gesture", @"current", @"visible"]);
}

BOOL NFBSplitTrollFrontmostApp(void) {
    if (!NSThread.isMainThread) return NO;
    // RootHide TrollOpen 1.5.2: +[TOJBBarGestureBridge splitFrontmostApplication], v16@0:8.
    // Let the plugin own the fullscreen-to-floating transition, rather than
    // pulling the foreground scene through its generic bundle-ID entry point.
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    SEL selector = NSSelectorFromString(@"splitFrontmostApplication");
    @try {
        if (![bridge respondsToSelector:selector]) return NO;
        NSMethodSignature *sig = [bridge methodSignatureForSelector:selector];
        if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void)) != 0) return NO;
        ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
        return YES;
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"TrollOpen foreground split failed: %@", error);
        return NO;
    }
}

// Close the current floating window. The precise selector differs between builds,
// so try the known-likely names in order and report which one answered. A void or
// BOOL return with zero arguments is accepted.
BOOL NFBCloseCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        id window = NFBTrollObject(bridge, @"currentVisibleFloatingWindow");
        NFBDebugLog(@"close: currentVisibleFloatingWindow=%@ class=%@",
                    window ?: @"<nil>", window ? NSStringFromClass([window class]) : @"<nil>");
        if (!window) return NO;
        NFBDumpFloatingWindowInterfaces(window);
        NSArray<NSString *> *candidates = @[@"closeCurrentFloatingWindow", @"closeFloatingWindow",
                                            @"dismissCurrentFloatingWindow", @"hideCurrentFloatingWindow",
                                            @"removeCurrentFloatingWindow", @"closeCurrentWindow"];
        for (NSString *name in candidates) {
            SEL selector = NSSelectorFromString(name);
            if (![window respondsToSelector:selector]) {
                NFBDebugLog(@"close: -%@ not available", name);
                continue;
            }
            NSMethodSignature *sig = [window methodSignatureForSelector:selector];
            char ret = sig ? sig.methodReturnType[0] : '?';
            if (!sig || sig.numberOfArguments != 2 || (ret != 'v' && ret != 'B' && ret != 'c')) {
                NFBDebugLog(@"close: -%@ signature mismatch ret=%c args=%lu", name, ret,
                            sig ? (unsigned long)sig.numberOfArguments : 0);
                continue;
            }
            ((void (*)(id, SEL))objc_msgSend)(window, selector);
            NFBDebugLog(@"close: invoked -%@ successfully", name);
            return YES;
        }
        NFBDebugLog(@"close: no usable close selector on the floating window");
        return NO;
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"TrollOpen close failed: %@", error);
        return NO;
    }
}

// Toggle the current floating window orientation (portrait <-> landscape).
// The official 1.3.7 binary exposes (on TOJBClass012) a read-only isLandscape
// BOOL and setContainerOrientation: taking a UIInterfaceOrientation integer.
// 1=Portrait, 3=LandscapeRight, 4=LandscapeLeft. This is the real interface
// behind the green bar's long-press "rotate" action.
BOOL NFBToggleOrientation(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        id window = NFBTrollObject(bridge, @"currentVisibleFloatingWindow");
        NFBDebugLog(@"rotate: currentVisibleFloatingWindow=%@ class=%@",
                    window ?: @"<nil>", window ? NSStringFromClass([window class]) : @"<nil>");
        if (!window) return NO;
        NFBDumpFloatingWindowInterfaces(window);
        // Read current landscape state (isLandscape, read-only BOOL).
        BOOL landscape = NO;
        SEL isLand = NSSelectorFromString(@"isLandscape");
        @try {
            if ([window respondsToSelector:isLand]) {
                NSMethodSignature *sig = [window methodSignatureForSelector:isLand];
                if (sig && sig.numberOfArguments == 2 &&
                    (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c'))
                    landscape = ((BOOL (*)(id, SEL))objc_msgSend)(window, isLand);
            }
        } @catch (__unused NSException *e) {}
        NFBDebugLog(@"rotate: isLandscape=%d", landscape);
        // Target the opposite orientation.
        NSInteger target = landscape ? 1 /* UIInterfaceOrientationPortrait */
                                     : 3 /* UIInterfaceOrientationLandscapeRight */;
        // Drive it through setContainerOrientation: (primary) or the siblings.
        for (NSString *name in @[@"setContainerOrientation:", @"setDeviceOrientation:", @"setSceneOrientation:"]) {
            SEL sel = NSSelectorFromString(name);
            if (![window respondsToSelector:sel]) {
                NFBDebugLog(@"rotate: -%@ not available", name);
                continue;
            }
            NSMethodSignature *sig = [window methodSignatureForSelector:sel];
            if (!sig || sig.numberOfArguments != 3 || sig.methodReturnType[0] != 'v') {
                NFBDebugLog(@"rotate: -%@ signature mismatch", name);
                continue;
            }
            char arg = [sig getArgumentTypeAtIndex:2][0];
            if (arg != 'q' && arg != 'i' && arg != 'l' && arg != 's') {
                NFBDebugLog(@"rotate: -%@ arg type %c unsupported", name, arg);
                continue;
            }
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(window, sel, target);
            NFBDebugLog(@"rotate: invoked -%@ target=%ld", name, (long)target);
            return YES;
        }
        NFBDebugLog(@"rotate: no usable orientation selector on the floating window");
        return NO;
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"TrollOpen orientation toggle failed: %@", error);
        return NO;
    }
}

static BOOL NFBTrollSignature(id target, SEL selector, BOOL hasFlag) {
    if (![target respondsToSelector:selector]) return NO;
    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
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
    // Verified against the supplied RootHide 1.5.2 binary's Objective-C metadata.
    // Its normal wrapper forwards to toj_showWithBundleID:skipOnlineLimitClose:
    // with NO. Call the wrapper, preserving TrollOpen's own behavior and checks.
    Class target = NSClassFromString(@"TOJBClass012");
    SEL open = NSSelectorFromString(@"TOJBMETHOD164:");
    SEL fingerprint = NSSelectorFromString(@"toj_showWithBundleID:skipOnlineLimitClose:");
    @try {
        if (!NFBTrollSignature(target, open, NO) || !NFBTrollSignature(target, fingerprint, YES)) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(target, open, bundleID);
        return YES;
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"TrollOpen open app failed: %@", error);
        return NO;
    }
}

static id NFBTrollObject(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    @try {
        NSMethodSignature *sig = [object methodSignatureForSelector:sel];
        if (![object respondsToSelector:sel] || !sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(object, sel);
    } @catch (__unused NSException *e) { return nil; }
}
NSString *NFBTrollVisibleApp(void) {
    if (!NSThread.isMainThread) return nil;
    id window = NFBTrollObject(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
    // A reduced mini-window is no longer the expanded split window.
    SEL mini = NSSelectorFromString(@"miniWindowModeEnabled");
    @try {
        NSMethodSignature *sig = [window methodSignatureForSelector:mini];
        if ([window respondsToSelector:mini] && sig.numberOfArguments == 2 &&
            (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c') &&
            ((BOOL (*)(id, SEL))objc_msgSend)(window, mini)) return nil;
    } @catch (__unused NSException *e) { return nil; }
    id app = NFBTrollObject(window, @"bundleID");
    return [app isKindOfClass:NSString.class] ? app : nil;
}
