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

// Fullscreen the current floating window. Unlike splitFrontmostApplication
// (a class method on TOJBBarGestureBridge), fullscreenCurrentFloatingWindow is
// an INSTANCE method on the floating window object (TOJBClass012) returned by
// +[TOJBBarGestureBridge currentVisibleFloatingWindow]. Call it on the instance.
BOOL NFBFullscreenCurrentFloatingWindow(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        id window = NFBTrollObject(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
        if (!window) return NO;
        SEL selector = NSSelectorFromString(@"fullscreenCurrentFloatingWindow");
        if (![window respondsToSelector:selector]) return NO;
        NSMethodSignature *sig = [window methodSignatureForSelector:selector];
        if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void)) != 0) return NO;
        ((void (*)(id, SEL))objc_msgSend)(window, selector);
        return YES;
    } @catch (__unused NSException *error) {
        NSLog(@"[NotifyBubbles] TrollOpen fullscreen failed");
        return NO;
    }
}

// Toggle orientation (the green bar's long-press "rotate" action). TrollOpen does
// not expose a clean no-arg "rotate floating window" selector; its rotation is
// surfaced through the bar-gesture command bridge. We attempt the command entry
// point handleBarGestureCommand: with the cmd_toggle_orientation token, and fall
// back to the floating window's own rotate method if that token path is absent.
BOOL NFBToggleOrientation(void) {
    if (!NSThread.isMainThread) return NO;
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    // Path 1: +[TOJBBarGestureBridge handleBarGestureCommand:].
    @try {
        SEL cmd = NSSelectorFromString(@"handleBarGestureCommand:");
        if ([bridge respondsToSelector:cmd]) {
            NSMethodSignature *sig = [bridge methodSignatureForSelector:cmd];
            if (sig && sig.numberOfArguments == 3 && sig.methodReturnType[0] == 'v' &&
                [sig getArgumentTypeAtIndex:2][0] == '@') {
                ((void (*)(id, SEL, id))objc_msgSend)(bridge, cmd, @"cmd_toggle_orientation");
                return YES;
            }
        }
    } @catch (__unused NSException *error) {}
    // Path 2: rotate the current floating window instance directly.
    @try {
        id window = NFBTrollObject(bridge, @"currentVisibleFloatingWindow");
        if (!window) return NO;
        for (NSString *name in @[@"rotateWindow", @"rotate", @"rotateToLandscape", @"toggleOrientation"]) {
            SEL sel = NSSelectorFromString(name);
            if (![window respondsToSelector:sel]) continue;
            NSMethodSignature *sig = [window methodSignatureForSelector:sel];
            if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != 'v') continue;
            ((void (*)(id, SEL))objc_msgSend)(window, sel);
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