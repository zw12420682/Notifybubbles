#import "NFBTrollOpen.h"
#import "NFBDebugLog.h"
#import <objc/message.h>
#include <string.h>

// Forward declaration: fetches an object-returning no-argument method result.
static id NFBTrollObject(id object, NSString *name);

// The TrollOpen selector set is not fully documented: the official 1.3.7 build
// and the 1.5.2 custom build differ, and control actions such as
// closeCurrentFloatingWindow live on the BRIDGE CLASS, not on the floating window
// instance. Dump the methods containing control-related keywords exactly once so
// the debug file reveals the correct selector names instead of us guessing again.
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

// Close the current floating window. The device-side method dump proved
// closeCurrentFloatingWindow is a CLASS method on TOJBBarGestureBridge
// (B16@0:8 on the metaclass), NOT an instance method on the floating window —
// which is why the earlier instance-based lookup always reported "unavailable".
BOOL NFBCloseCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        SEL selector = NSSelectorFromString(@"closeCurrentFloatingWindow");
        if (bridge && [bridge respondsToSelector:selector]) {
            NSMethodSignature *sig = [bridge methodSignatureForSelector:selector];
            char ret = sig ? sig.methodReturnType[0] : '?';
            if (sig && sig.numberOfArguments == 2 && (ret == 'v' || ret == 'B' || ret == 'c')) {
                ((void (*)(id, SEL))objc_msgSend)(bridge, selector);
                NFBDebugLog(@"close: invoked +[TOJBBarGestureBridge closeCurrentFloatingWindow]");
                return YES;
            }
            NFBDebugLog(@"close: class method signature mismatch ret=%c args=%lu", ret,
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
            NSMethodSignature *sig = [window methodSignatureForSelector:sel];
            if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != 'v') continue;
            ((void (*)(id, SEL))objc_msgSend)(window, sel);
            NFBDebugLog(@"close: invoked -%@ (fallback)", name);
            return YES;
        }
        NFBDebugLog(@"close: no usable close path");
        return NO;
    } @catch (__unused NSException *error) {
        NFBDebugLog(@"TrollOpen close failed: %@", error);
        return NO;
    }
}

// Read a zero-argument NSInteger/int property into `out`; NO when unavailable.
static BOOL NFBReadInteger(id object, NSString *name, NSInteger *out) {
    if (!object || !out) return NO;
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return NO;
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 2) return NO;
    char ret = sig.methodReturnType[0];
    if (ret == 'q' || ret == 'l') *out = ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
    else if (ret == 'i') *out = (NSInteger)((int (*)(id, SEL))objc_msgSend)(object, selector);
    else return NO;
    return YES;
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
        // isLandscape does NOT exist on this build — the device-side method dump
        // lists only containerOrientation / sceneOrientation (both `q`). Reading a
        // nonexistent isLandscape always yielded NO, so the window could only ever
        // be rotated one way. Read the real orientation integer instead.
        NSInteger current = 0;
        BOOL known = NO;
        for (NSString *name in @[@"containerOrientation", @"sceneOrientation"]) {
            if (NFBReadInteger(window, name, &current)) {
                known = YES;
                NFBDebugLog(@"rotate: %@=%ld", name, (long)current);
                break;
            }
            NFBDebugLog(@"rotate: -%@ unavailable", name);
        }
        NSInteger target;
        if (known) {
            // 1 = UIInterfaceOrientationPortrait; anything else counts as landscape.
            target = (current == 1) ? 3 /* LandscapeRight */ : 1 /* Portrait */;
        } else {
            // Legacy fallback path for builds that only expose the BOOL.
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
            NFBDebugLog(@"rotate: fallback isLandscape=%d", landscape);
            target = landscape ? 1 : 3;
        }
        NFBDebugLog(@"rotate: known=%d current=%ld -> target=%ld", known, (long)current, (long)target);
        // Drive it through setContainerOrientation: (primary) or the siblings.
        for (NSString *name in @[@"setContainerOrientation:", @"setSceneOrientation:", @"setDeviceOrientation:"]) {
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
