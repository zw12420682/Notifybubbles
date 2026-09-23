#import "NFBWindowControls.h"
#import "NFBTrollOpen.h"
#import "NFBSplitClosePolicy.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <string.h>

static __weak UIView *lastWindow;
static NSString *lastApp;
static NSUInteger placementGeneration;
static id currentWindow(void) {
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    SEL sel = NSSelectorFromString(@"currentVisibleFloatingWindow");
    NSMethodSignature *sig = [bridge methodSignatureForSelector:sel];
    if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(bridge, sel);
}
CGRect NFBSplitFrameInView(UIView *root) {
    if (!NSThread.isMainThread || !root.window) return CGRectNull;
    @try {
        id object = currentWindow();
        if (![object isKindOfClass:UIView.class]) return CGRectNull;
        UIView *view = object;
        if (!view.window || view.hidden || CGRectIsEmpty(view.bounds)) return CGRectNull;
        return [view convertRect:view.bounds toView:root];
    } @catch (__unused NSException *exception) { return CGRectNull; }
}
static NSInteger orientationOf(id window, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [window methodSignatureForSelector:selector];
    if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(NSInteger))) return 0;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(window, selector);
}
static NSInteger boolStateOf(id window, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [window methodSignatureForSelector:selector];
    if (sig.numberOfArguments != 2 ||
        (sig.methodReturnType[0] != 'B' && sig.methodReturnType[0] != 'c')) return -1;
    return ((BOOL (*)(id, SEL))objc_msgSend)(window, selector) ? 1 : 0;
}
void NFBObserveSplitSwitch(NSString *app, BOOL enabled) {
    static __weak UIView *previousWindow;
    static NSString *previousApp;
    static __weak UIView *pendingWindow;
    static NSString *pendingApp;
    static NSTimeInterval portraitSince;
    if (!NSThread.isMainThread) return;
    // A minimized/dismissed current window ends this switch session.
    if (!app.length) {
        previousWindow = nil; previousApp = nil;
        pendingWindow = nil; pendingApp = nil; portraitSince = 0;
        return;
    }
    @try {
        id object = currentWindow();
        if (![object isKindOfClass:UIView.class]) return;
        BOOL changed = previousWindow != object || ![previousApp isEqual:app];
        if (changed) {
            // Keep only the immediately preceding window for this current app.
            pendingWindow = enabled && previousWindow != object && ![previousApp isEqual:app]
                ? previousWindow : nil;
            pendingApp = pendingWindow ? previousApp : nil;
            portraitSince = 0;
            previousWindow = object; previousApp = [app copy];
        }
        if (!enabled) { pendingWindow = nil; pendingApp = nil; portraitSince = 0; return; }
        UIView *previous = pendingWindow;
        if (!previous || previous == object) return;
        NSInteger scene = orientationOf(object, @"sceneOrientation");
        NSInteger container = orientationOf(object, @"containerOrientation");
        // Landscape or unknown current orientation defers closing the old window.
        // Require stable portrait so opening/rotation intermediate states cannot
        // briefly report portrait and prematurely close the previous app.
        if (!NFBShouldClosePreviousSplit(boolStateOf(object, @"miniWindowModeEnabled"),
                boolStateOf(object, @"isTransitioningFromMiniMode"), scene, container)) {
            portraitSince = 0;
            return;
        }
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (!portraitSince) { portraitSince = now; return; }
        if (now - portraitSince < 0.35) return;
        NSString *oldApp = pendingApp;
        pendingWindow = nil; pendingApp = nil; portraitSince = 0;
        // Preserve the existing protection for old landscape and corner windows.
        if (!NFBShouldClosePreviousSplit(boolStateOf(previous, @"miniWindowModeEnabled"),
                boolStateOf(previous, @"isTransitioningFromMiniMode"),
                orientationOf(previous, @"sceneOrientation"),
                orientationOf(previous, @"containerOrientation"))) return;
        SEL close = NSSelectorFromString(@"closeWindowWithoutTerminatingProcessWithoutAnimation");
        NSMethodSignature *sig = [previous methodSignatureForSelector:close];
        if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void))) return;
        // Always target the saved previous window; never close the current app.
        ((void (*)(id, SEL))objc_msgSend)(previous, close);
        NFBDebugLog(@"split-switch: current %@ settled portrait; closed previous %@", app, oldApp);
    } @catch (NSException *exception) { NFBDebugLog(@"split-switch: %@", exception); }
}
BOOL NFBCurrentSplitLandscape(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        id window = currentWindow();
        NSInteger scene = orientationOf(window, @"sceneOrientation");
        NSInteger container = orientationOf(window, @"containerOrientation");
        return scene == 3 || scene == 4 || container == 3 || container == 4;
    } @catch (__unused NSException *exception) { return NO; }
}
void NFBResetSplitPlacement(void) {
    lastApp = nil; lastWindow = nil; placementGeneration++;
}
void NFBObserveSplitPlacement(NSString *app) {
    if (!NSThread.isMainThread) return;
    if (!app.length) { NFBResetSplitPlacement(); return; }
    @try {
        id object = currentWindow();
        if (![object isKindOfClass:UIView.class]) return;
        UIView *view = object;
        if (lastWindow == view && [lastApp isEqual:app]) return;
        lastWindow = view; lastApp = [app copy];
        NSUInteger generation = ++placementGeneration;
        __weak UIView *weakWindow = view;
        // Let TrollOpen finish restoring its previous layout before applying ours.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIView *window = weakWindow;
            if (NFBCurrentSplitLandscape()) return;
            if (!window || generation != placementGeneration || currentWindow() != window ||
                ![NFBTrollVisibleApp() isEqual:app] ||
                (!window.superview && ![window isKindOfClass:UIWindow.class])) return;
            @try {
                SEL scale = NSSelectorFromString(@"setVisualScale:");
                NSMethodSignature *sig = [window methodSignatureForSelector:scale];
                if (sig.numberOfArguments != 3 || strcmp(sig.methodReturnType, @encode(void)) ||
                    strcmp([sig getArgumentTypeAtIndex:2], @encode(double))) return;
                ((void (*)(id, SEL, double))objc_msgSend)(window, scale, 0.86);
                [window setNeedsLayout]; [window layoutIfNeeded];
                UIView *parent = window.superview;
                CGRect area = parent ? [parent convertRect:parent.window.bounds fromView:parent.window]
                    : ((UIWindow *)window).screen.bounds;
                CGRect frame = window.frame;
                if (CGRectIsEmpty(frame) || CGRectIsEmpty(area)) return;
                // Adjust center using the rendered frame, preserving rotation/transform.
                CGPoint center = window.center;
                center.x += CGRectGetMinX(area) - CGRectGetMinX(frame);
                center.y += CGRectGetMaxY(area) - CGRectGetMaxY(frame);
                window.center = center;
                NFBDebugLog(@"placement: %@ requested scale=0.86 frame=%@", app, NSStringFromCGRect(window.frame));
            } @catch (NSException *exception) { NFBDebugLog(@"placement: %@", exception); }
        });
    } @catch (NSException *exception) { NFBDebugLog(@"placement lookup: %@", exception); }
}
