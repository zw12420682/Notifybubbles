#import "NFBTrollOpen.h"
#import <objc/message.h>
#include <string.h>

// Forward declaration: fetches an object-returning no-argument method result.
static id NFBTrollObject(id object, NSString *name);

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
        NSLog(@"[NotifyBubbles] TrollOpen foreground split failed");
        return NO;
    }
}

// Close the current floating window. closeCurrentFloatingWindow is an INSTANCE
// method on the floating window object (TOJBClass012) returned by
// +[TOJBBarGestureBridge currentVisibleFloatingWindow]. Call it on the instance.
BOOL NFBCloseCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        id window = NFBTrollObject(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
        if (!window) return NO;
        SEL selector = NSSelectorFromString(@"closeCurrentFloatingWindow");
        if (![window respondsToSelector:selector]) return NO;
        NSMethodSignature *sig = [window methodSignatureForSelector:selector];
        if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void)) != 0) return NO;
        ((void (*)(id, SEL))objc_msgSend)(window, selector);
        return YES;
    } @catch (__unused NSException *error) {
        NSLog(@"[NotifyBubbles] TrollOpen close failed");
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
        id window = NFBTrollObject(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
        if (!window) return NO;
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
        // Target the opposite orientation.
        NSInteger target = landscape ? 1 /* UIInterfaceOrientationPortrait */
                                     : 3 /* UIInterfaceOrientationLandscapeRight */;
        // Drive it through setContainerOrientation: (primary) or setDeviceOrientation: (fallback).
        for (NSString *name in @[@"setContainerOrientation:", @"setDeviceOrientation:"]) {
            SEL sel = NSSelectorFromString(name);
            if (![window respondsToSelector:sel]) continue;
            NSMethodSignature *sig = [window methodSignatureForSelector:sel];
            if (!sig || sig.numberOfArguments != 3 || sig.methodReturnType[0] != 'v') continue;
            char arg = [sig getArgumentTypeAtIndex:2][0];
            if (arg != 'q' && arg != 'i' && arg != 'l' && arg != 's') continue;
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(window, sel, target);
            return YES;
        }
    } @catch (__unused NSException *error) {}
    NSLog(@"[NotifyBubbles] TrollOpen orientation toggle unavailable");
    return NO;
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
        NSLog(@"[NotifyBubbles] TrollOpen adapter unavailable or failed");
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