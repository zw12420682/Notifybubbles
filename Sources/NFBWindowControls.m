#import "NFBWindowControls.h"
#import "NFBTrollOpen.h"
#import "NFBWindowState.h"
#import "NFBInterfaces.h"
#import "NFBRightEdgeAction.h"
#import "NFBTopAction.h"
#import "NFBSplitClosePolicy.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <string.h>

static __weak UIView *lastWindow;
static NSString *lastApp;
static NSUInteger placementGeneration;
static id currentWindow(void) {
    return NFBCurrentWindowState().floatingWindow;
}
static UIView *attachmentWindow(void);
CGRect NFBSplitFrameInView(UIView *root) {
    if (!NSThread.isMainThread || !root.window) return CGRectNull;
    @try {
        id object = attachmentWindow();
        if (![object isKindOfClass:UIView.class]) return CGRectNull;
        UIView *view = object;
        if (!view.window || view.hidden || CGRectIsEmpty(view.bounds)) return CGRectNull;
        return [view convertRect:view.bounds toView:root];
    } @catch (__unused NSException *exception) { return CGRectNull; }
}
static NSInteger orientationOf(id window, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = NFBSignature(window, selector);
    if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(NSInteger))) return 0;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(window, selector);
}
static NSInteger boolStateOf(id window, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = NFBSignature(window, selector);
    if (sig.numberOfArguments != 2 ||
        (sig.methodReturnType[0] != 'B' && sig.methodReturnType[0] != 'c')) return -1;
    return ((BOOL (*)(id, SEL))objc_msgSend)(window, selector) ? 1 : 0;
}
// Search the actual visible view hierarchy, front to back. No window activation
// or lifecycle action is performed while choosing an attachment target.
static NSString *appOfWindow(UIView *view) {
    SEL selector = NSSelectorFromString(@"bundleID");
    NSMethodSignature *sig = NFBSignature(view, selector);
    if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    id app = ((id (*)(id, SEL))objc_msgSend)(view, selector);
    return [app isKindOfClass:NSString.class] ? app : nil;
}
static BOOL visibleView(UIView *view) {
    if (!view.window || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
    CGRect rect = [view convertRect:view.bounds toView:view.window];
    return CGRectIntersectsRect(rect, view.window.bounds);
}
static UIView *floatingInTree(UIView *view, Class floatingClass, BOOL landscape) {
    if (view.hidden || view.alpha < 0.01) return nil;
    // A floating window is a candidate as a whole; its app content need not be scanned.
    if ([view isKindOfClass:floatingClass]) {
        if (!visibleView(view) || !appOfWindow(view).length ||
            boolStateOf(view, @"isClosingWithKeepAliveAnimation") == 1) return nil;
        NSInteger kind = NFBExpandedWindowKind(boolStateOf(view, @"miniWindowModeEnabled"),
            boolStateOf(view, @"isTransitioningFromMiniMode"),
            orientationOf(view, @"sceneOrientation"), orientationOf(view, @"containerOrientation"));
        return kind == (landscape ? 2 : 1) ? view : nil;
    }
    // zPosition overrides subview order; reversed stable order breaks ties.
    NSArray<UIView *> *frontFirst = [[view.subviews reverseObjectEnumerator].allObjects
        sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            if (a.layer.zPosition > b.layer.zPosition) return NSOrderedAscending;
            if (a.layer.zPosition < b.layer.zPosition) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    for (UIView *child in frontFirst) {
        UIView *found = floatingInTree(child, floatingClass, landscape);
        if (found) return found;
    }
    return nil;
}
static UIView *frontmostFloatingWindow(BOOL landscape) {
    if (!NSThread.isMainThread) return nil;
    static NFBWindowState *sample;
    static __weak UIView *portrait, *wide;
    static BOOL portraitRead, wideRead;
    NFBWindowState *now = NFBCurrentWindowState();
    if (sample != now) { sample = now; portraitRead = NO; wideRead = NO; portrait = nil; wide = nil; }
    if (landscape ? wideRead : portraitRead) return landscape ? wide : portrait;
    if (landscape) wideRead = YES; else portraitRead = YES;
    @try {
        Class floatingClass = NSClassFromString(@"FloatingAppWindow");
        if (!floatingClass) return nil;
        NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateBackground ||
                scene.activationState == UISceneActivationStateUnattached) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
        // SpringBoard may also own windows outside a foreground UIWindowScene.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
        NSArray<UIWindow *> *frontFirst = [[windows.array reverseObjectEnumerator].allObjects
            sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
                if (a.windowLevel > b.windowLevel) return NSOrderedAscending;
                if (a.windowLevel < b.windowLevel) return NSOrderedDescending;
                return NSOrderedSame;
            }];
        for (UIWindow *window in frontFirst) {
            UIView *candidate = floatingInTree(window, floatingClass, landscape);
            if (candidate) { if (landscape) wide = candidate; else portrait = candidate; return candidate; }
        }
    } @catch (NSException *exception) { NFBDebugLog(@"floating lookup: %@", exception); }
    return nil;
}
static UIView *attachmentWindow(void) {
    if (!NSThread.isMainThread) return nil;
    @try {
        id current = currentWindow();
        if (NFBTrollVisibleApp().length && [current isKindOfClass:UIView.class] && visibleView(current) &&
            boolStateOf(current, @"isClosingWithKeepAliveAnimation") != 1 &&
            NFBShouldClosePreviousSplit(boolStateOf(current, @"miniWindowModeEnabled"),
                boolStateOf(current, @"isTransitioningFromMiniMode"),
                orientationOf(current, @"sceneOrientation"), orientationOf(current, @"containerOrientation"))) return current;
        return frontmostFloatingWindow(NO);
    } @catch (NSException *exception) { NFBDebugLog(@"attachment lookup: %@", exception); return nil; }
}
UIView *NFBTopActionWindow(void) {
    // Any expanded landscape window wins, even with a portrait window in front.
    return frontmostFloatingWindow(YES) ?: attachmentWindow();
}
BOOL NFBWindowIsLandscape(UIView *window) {
    @try {
        return NFBExpandedWindowKind(boolStateOf(window, @"miniWindowModeEnabled"),
            boolStateOf(window, @"isTransitioningFromMiniMode"),
            orientationOf(window, @"sceneOrientation"), orientationOf(window, @"containerOrientation")) == 2;
    } @catch (__unused NSException *exception) { return NO; }
}
CGRect NFBWindowFrameInView(UIView *window, UIView *root) {
    if (!NSThread.isMainThread || !root.window || !window) return CGRectNull;
    @try { return visibleView(window) ? [window convertRect:window.bounds toView:root] : CGRectNull; }
    @catch (__unused NSException *exception) { return CGRectNull; }
}
NSString *NFBSplitAttachmentApp(void) {
    @try { return appOfWindow(attachmentWindow()); }
    @catch (__unused NSException *exception) { return nil; }
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
        NSMethodSignature *sig = NFBSignature(previous, close);
        if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void))) return;
        // Always target the saved previous window; never close the current app.
        ((void (*)(id, SEL))objc_msgSend)(previous, close);
        NFBInvalidateWindowState();
        NFBDebugLog(@"split-switch: current %@ settled portrait; closed previous %@", app, oldApp);
    } @catch (NSException *exception) { NFBDebugLog(@"split-switch: %@", exception); }
}
BOOL NFBCurrentSplitLandscape(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        id window = attachmentWindow();
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
            // Placement follows the actual current window, not the rail fallback.
            NSInteger scene = orientationOf(window, @"sceneOrientation");
            NSInteger container = orientationOf(window, @"containerOrientation");
            if (scene == 3 || scene == 4 || container == 3 || container == 4) return;
            if (!window || generation != placementGeneration || currentWindow() != window ||
                ![NFBTrollVisibleApp() isEqual:app] ||
                (!window.superview && ![window isKindOfClass:UIWindow.class])) return;
            @try {
                SEL scale = NSSelectorFromString(@"setVisualScale:");
                NSMethodSignature *sig = NFBSignature(window, scale);
                if (sig.numberOfArguments != 3 || strcmp(sig.methodReturnType, @encode(void)) ||
                    strcmp([sig getArgumentTypeAtIndex:2], @encode(double))) return;
                SEL sync = NSSelectorFromString(@"syncContainerFrameToVisualScalePreservingCenter:");
                NSMethodSignature *syncSig = NFBSignature(window, sync);
                if (syncSig.numberOfArguments != 3 || strcmp(syncSig.methodReturnType, @encode(void)) ||
                    strcmp([syncSig getArgumentTypeAtIndex:2], @encode(BOOL))) return;
                ((void (*)(id, SEL, double))objc_msgSend)(window, scale, 0.86);
                ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sync, YES);
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

// Supply the ended tap expected by the original handler without dispatching a
// second UIKit event, changing the real recognizer, or creating a screen touch.
@interface NFBRightEdgeTap : UITapGestureRecognizer
@property(nonatomic, weak) UIView *edgeRegion;
@end
@implementation NFBRightEdgeTap
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateEnded; }
- (UIView *)view { return self.edgeRegion; }
- (CGPoint)locationInView:(UIView *)view {
    UIView *region = self.edgeRegion;
    return [region convertPoint:CGPointMake(CGRectGetMidX(region.bounds), CGRectGetMidY(region.bounds)) toView:view];
}
@end

BOOL NFBCloseCurrentSplit(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        UIView *window = NFBTrollVisibleApp().length ? currentWindow() : attachmentWindow();
        if (![window isKindOfClass:UIView.class] || !visibleView(window) ||
            boolStateOf(window, @"miniWindowModeEnabled") != 0 ||
            boolStateOf(window, @"isClosingWithKeepAliveAnimation") == 1) return NO;
        SEL getter = NSSelectorFromString(@"rightTouchRegion");
        NSMethodSignature *sig = NFBSignature(window, getter);
        if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return NO;
        id region = ((id (*)(id, SEL))objc_msgSend)(window, getter);
        if (![region isKindOfClass:UIView.class] || ![region isDescendantOfView:window]) {
            NFBErrorLog(@"orange-close: rightTouchRegion unavailable");
            return NO;
        }
        NFBRightEdgeTap *tap = [NFBRightEdgeTap new]; tap.edgeRegion = region;
        BOOL sent = NFBDispatchRightEdgeTap(window, tap);
        if (sent) NFBInvalidateWindowState();
        NFBDebugLog(@"orange-close: original right-region tap dispatched=%d app=%@", sent, appOfWindow(window));
        return sent;
    } @catch (NSException *exception) { NFBDebugLog(@"orange-close: %@", exception); return NO; }
}

@interface NFBTopLongPress : UILongPressGestureRecognizer
@property(nonatomic, weak) UIView *titleRegion;
@end
@implementation NFBTopLongPress
// Binary handleTopTouchLongPress: compares recognizer.state with 1 (Began).
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateBegan; }
- (UIView *)view { return self.titleRegion; }
- (CGPoint)locationInView:(UIView *)view {
    UIView *region = self.titleRegion;
    return [region convertPoint:CGPointMake(CGRectGetMidX(region.bounds), CGRectGetMidY(region.bounds)) toView:view];
}
@end
BOOL NFBPerformTopLongPress(UIView *window) {
    if (!NSThread.isMainThread || !window) return NO;
    @try {
        if (!visibleView(window) || boolStateOf(window, @"isClosingWithKeepAliveAnimation") == 1 ||
            !NFBExpandedWindowKind(boolStateOf(window, @"miniWindowModeEnabled"),
                boolStateOf(window, @"isTransitioningFromMiniMode"),
                orientationOf(window, @"sceneOrientation"), orientationOf(window, @"containerOrientation"))) return NO;
        SEL getter = NSSelectorFromString(@"titleBar");
        NSMethodSignature *sig = NFBSignature(window, getter);
        if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return NO;
        id region = ((id (*)(id, SEL))objc_msgSend)(window, getter);
        if (![region isKindOfClass:UIView.class] || ![region isDescendantOfView:window]) return NO;
        NFBTopLongPress *gesture = [NFBTopLongPress new]; gesture.titleRegion = region;
        BOOL sent = NFBDispatchTopLongPress(window, gesture);
        if (sent) NFBInvalidateWindowState();
        NFBDebugLog(@"top-long-press: dispatched=%d app=%@", sent, appOfWindow(window));
        return sent;
    } @catch (NSException *exception) { NFBDebugLog(@"top-long-press: %@", exception); return NO; }
}

// Re-submit the settled portrait scene request once, then reconcile the host.
// 324 delegates to pipSceneHandle client-orientation updates; 404 only lays out the host.
// updateHostViewLayoutForCurrentBounds is the original host bounds/transform layout routine used by 343.
void NFBObserveRotationLayout(void) {
    if (!NSThread.isMainThread) return;
    static NSMapTable<UIView *, NSMutableDictionary *> *states;
    if (!states) states = [NSMapTable weakToStrongObjectsMapTable];
    @try {
        id object = currentWindow();
        if (![object isKindOfClass:UIView.class]) return;
        UIView *window = object;
        if (!visibleView(window) || boolStateOf(window, @"miniWindowModeEnabled") != 0 ||
            boolStateOf(window, @"isTransitioningFromMiniMode") != 0 ||
            boolStateOf(window, @"isClosingWithKeepAliveAnimation") != 0) return;
        NSInteger scene = orientationOf(window, @"sceneOrientation"), container = orientationOf(window, @"containerOrientation");
        NSMutableDictionary *state = [states objectForKey:window];
        if (!state) { state = [NSMutableDictionary dictionary]; [states setObject:state forKey:window]; }
        if (scene >= 3 || container >= 3) { state[@"landscape"] = @YES; [state removeObjectForKey:@"since"]; [state removeObjectForKey:@"requested"]; return; }
        if (![state[@"landscape"] boolValue] || scene < 1 || scene > 2 || container != scene) return;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        NSValue *bounds = [NSValue valueWithCGRect:window.bounds];
        if (![state[@"bounds"] isEqual:bounds] || !state[@"since"]) {
            state[@"bounds"] = bounds; state[@"since"] = @(now); return;
        }
        if (now - [state[@"since"] doubleValue] < 0.65) return;
        if (!state[@"requested"]) {
            SEL request = NSSelectorFromString(@"requestSceneOrientationOnce:");
            NSMethodSignature *requestSig = NFBSignature(window, request);
            if (requestSig.numberOfArguments != 3 || strcmp(requestSig.methodReturnType, @encode(void)) ||
                strcmp([requestSig getArgumentTypeAtIndex:2], @encode(NSInteger))) {
                state[@"landscape"] = @NO;
                NFBErrorLog(@"portrait-content: scene request unavailable app=%@", appOfWindow(window));
                return;
            }
            // Mark before dispatch so a synchronous callback cannot send twice.
            state[@"requested"] = @(now);
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(window, request, scene);
            NFBDebugLog(@"portrait-content: resubmitted orientation=%ld app=%@", (long)scene, appOfWindow(window));
            return;
        }
        if (now - [state[@"requested"] doubleValue] < 0.35) return;
        state[@"landscape"] = @NO;
        SEL layout = NSSelectorFromString(@"updateHostViewLayoutForCurrentBounds");
        NSMethodSignature *sig = NFBSignature(window, layout);
        if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void))) return;
        [UIView performWithoutAnimation:^{
            ((void (*)(id, SEL))objc_msgSend)(window, layout);
            [window setNeedsLayout]; [window layoutIfNeeded];
        }];
        NFBDebugLog(@"portrait-content: reconciled app=%@ bounds=%@", appOfWindow(window), bounds);
    } @catch (NSException *exception) { NFBDebugLog(@"portrait-content: %@", exception); }
}
