#import "NFBWindowControls.h"
#import "NFBTrollOpen.h"
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
BOOL NFBRotateSplitWindow(void) {
    if (!NSThread.isMainThread || !NFBTrollVisibleApp().length) return NO;
    @try {
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        SEL sel = NSSelectorFromString(@"handleBarGestureCommand:");
        NSMethodSignature *sig = [bridge methodSignatureForSelector:sel];
        if (sig.numberOfArguments != 3 || [sig getArgumentTypeAtIndex:2][0] != '@' ||
            (sig.methodReturnType[0] != 'B' && sig.methodReturnType[0] != 'c')) return NO;
        BOOL accepted = ((BOOL (*)(id, SEL, id))objc_msgSend)(bridge, sel, @"cmd_toggle_orientation");
        NFBDebugLog(@"rotation: accepted=%d", accepted);
        return accepted;
    } @catch (NSException *exception) {
        NFBDebugLog(@"rotation: %@", exception); return NO;
    }
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
                CGRect area = parent ? UIEdgeInsetsInsetRect(parent.bounds, parent.safeAreaInsets)
                    : ((UIWindow *)window).screen.bounds;
                CGRect frame = window.frame;
                if (CGRectIsEmpty(frame) || CGRectIsEmpty(area)) return;
                // Adjust center using the rendered frame, preserving rotation/transform.
                CGPoint center = window.center;
                center.x += CGRectGetMinX(area) + 8 - CGRectGetMinX(frame);
                center.y += CGRectGetMaxY(area) - 8 - CGRectGetMaxY(frame);
                window.center = center;
                NFBDebugLog(@"placement: %@ requested scale=0.86 frame=%@", app, NSStringFromCGRect(window.frame));
            } @catch (NSException *exception) { NFBDebugLog(@"placement: %@", exception); }
        });
    } @catch (NSException *exception) { NFBDebugLog(@"placement lookup: %@", exception); }
}
