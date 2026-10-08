#import "NFBWindowControls.h"
#import "NFBTrollOpen.h"
#import "NFBRightEdgeAction.h"
#import "NFBTopAction.h"
#import "NFBSplitClosePolicy.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <string.h>
#include <stdlib.h>
#import "NFBArrangement.h"
#import "NFBOpenEdge.h"

static NSString *arrangementSignature;
static NSTimeInterval arrangementSince;
static NSMapTable *arrangementStates;
static NSUInteger arrangementOrder;
static id currentWindow(void) {
    Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
    SEL sel = NSSelectorFromString(@"currentVisibleFloatingWindow");
    NSMethodSignature *sig = [bridge methodSignatureForSelector:sel];
    if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(bridge, sel);
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
// Search the actual visible view hierarchy, front to back. No window activation
// or lifecycle action is performed while choosing an attachment target.
static NSString *appOfWindow(UIView *view) {
    SEL selector = NSSelectorFromString(@"bundleID");
    NSMethodSignature *sig = [view methodSignatureForSelector:selector];
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
            if (candidate) return candidate;
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
static BOOL hasMiniInTree(UIView *view, Class floatingClass) {
    if (view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:floatingClass]) {
        if (boolStateOf(view, @"isClosingWithKeepAliveAnimation") == 1) return NO;
        return boolStateOf(view, @"miniWindowModeEnabled") == 1;
    }
    for (UIView *child in view.subviews)
        if (hasMiniInTree(child, floatingClass)) return YES;
    return NO;
}
// YES when at least one corner mini window is currently visible.
static BOOL NFBHasMiniWindows(void) {
    if (!NSThread.isMainThread) return NO;
    @try {
        Class floatingClass = NSClassFromString(@"FloatingAppWindow");
        if (!floatingClass) return NO;
        NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateBackground ||
                scene.activationState == UISceneActivationStateUnattached) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
        for (UIWindow *window in windows)
            if (hasMiniInTree(window, floatingClass)) return YES;
    } @catch (NSException *exception) { NFBDebugLog(@"mini-scan: %@", exception); }
    return NO;
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
        // With other mini windows present, shrink the previous portrait split into
        // a mini window so it joins them; otherwise close it as before.
        if (NFBHasMiniWindows()) {
            if (NFBMinimizeFloatingWindow(previous))
                NFBDebugLog(@"split-switch: current %@ settled portrait; minimized previous %@", app, oldApp);
            else
                NFBDebugLog(@"split-switch: current %@ settled portrait; minimize previous %@ failed", app, oldApp);
        } else {
            SEL close = NSSelectorFromString(@"closeWindowWithoutTerminatingProcessWithoutAnimation");
            NSMethodSignature *sig = [previous methodSignatureForSelector:close];
            if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void))) return;
            // Always target the saved previous window; never close the current app.
            ((void (*)(id, SEL))objc_msgSend)(previous, close);
            NFBDebugLog(@"split-switch: current %@ settled portrait; closed previous %@", app, oldApp);
        }
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
static void collectArrangement(UIView *view, Class cls, NSMutableOrderedSet *result) {
    if (view.hidden || view.alpha < 0.01) return;
    if ([view isKindOfClass:cls]) {
        if (visibleView(view) && boolStateOf(view, @"isClosingWithKeepAliveAnimation") != 1)
            [result addObject:view];
        return;
    }
    for (UIView *child in view.subviews) collectArrangement(child, cls, result);
}
static BOOL busyArrangement(UIView *view) {
    for (UIGestureRecognizer *gesture in view.gestureRecognizers)
        if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) return YES;
    // Only check window chrome; do not traverse the app's hosted scene.
    for (UIView *child in view.subviews)
        for (UIGestureRecognizer *gesture in child.gestureRecognizers)
            if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) return YES;
    return NO;
}
void NFBResetSplitPlacement(void) { arrangementSignature = nil; arrangementSince = CACurrentMediaTime(); }
void NFBObserveSplitPlacement(NSString *app) {
    (void)app;
    if (!NSThread.isMainThread) return;
    @try {
        Class cls = NSClassFromString(@"FloatingAppWindow");
        if (!cls) return;
        if (!arrangementStates) arrangementStates = [NSMapTable weakToStrongObjectsMapTable];
        NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) collectArrangement(window, cls, found);
#pragma clang diagnostic pop
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState != UISceneActivationStateBackground && scene.activationState != UISceneActivationStateUnattached)
                for (UIWindow *window in ((UIWindowScene *)scene).windows) collectArrangement(window, cls, found);
        BOOL hasLandscape = NO, hasPortrait = NO, rotatedToLandscape = NO;
        NSMutableArray *participants = [NSMutableArray array];
        for (UIView *view in found) {
            if (busyArrangement(view) || boolStateOf(view, @"isTransitioningFromMiniMode") == 1) {
                arrangementSince = CACurrentMediaTime(); return;
            }
            NSInteger mini = boolStateOf(view, @"miniWindowModeEnabled");
            NSInteger scene = orientationOf(view, @"sceneOrientation");
            NSInteger container = orientationOf(view, @"containerOrientation");
            NSInteger kind = mini == 1 ? 3 : NFBExpandedWindowKind(mini, 0, scene, container);
            if (!kind) { arrangementSince = CACurrentMediaTime(); return; }
            NSMutableDictionary *state = [arrangementStates objectForKey:view];
            if (!state) {
                state = [@{@"order": @(++arrangementOrder)} mutableCopy];
                [arrangementStates setObject:state forKey:view];
            }
            NSInteger previous = [state[@"kind"] integerValue];
            if (previous == 1 && kind == 2) rotatedToLandscape = YES;
            // The window's current transform gives its natural rendered size.
            state[@"base"] = [NSValue valueWithCGAffineTransform:view.transform];
            state[@"kind"] = @(kind);
            hasLandscape |= kind == 2; hasPortrait |= kind == 1;
        }
        if (rotatedToLandscape && !hasPortrait) NFBOpenEdgeExpandAfterRotation();
        // Mini windows participate too: they form a horizontal row at the top,
        // left to right, instead of being left to the host's corner-avoidance.
        for (UIView *view in found) [participants addObject:view];
        [participants sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            NSDictionary *sa = [arrangementStates objectForKey:a], *sb = [arrangementStates objectForKey:b];
            NSInteger ka = [sa[@"kind"] integerValue], kb = [sb[@"kind"] integerValue];
            NSInteger ra = ka == 3 ? 0 : (ka == 2 ? 1 : 2), rb = kb == 3 ? 0 : (kb == 2 ? 1 : 2);
            return ra == rb ? [sa[@"order"] compare:sb[@"order"]] : (ra < rb ? NSOrderedAscending : NSOrderedDescending);
        }];
        UIScreen *screen = ((UIView *)participants.firstObject).window.screen;
        CGRect area = screen.bounds;
        if (!participants.count || !screen || CGRectIsEmpty(area)) { arrangementSignature = nil; return; }
        id savedPosition = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("LandscapeVerticalPosition"), CFSTR("local.notifybubbles")));
        double position = [savedPosition isKindOfClass:NSNumber.class] ? [savedPosition doubleValue] / 100.0 : 0;
        if (!isfinite(position)) position = 0;
        position = MAX(0, MIN(1, position));
        NSMutableString *signature = [NSMutableString stringWithFormat:@"%@|position=%.6f", NSStringFromCGRect(area), position];
        for (UIView *view in participants) {
            NSDictionary *state = [arrangementStates objectForKey:view];
            [signature appendFormat:@"|%@:%@:%@:%@", state[@"order"], state[@"kind"], NSStringFromCGRect(view.bounds), state[@"base"]];
        }
        if (![signature isEqual:arrangementSignature]) {
            arrangementSignature = [signature copy]; arrangementSince = CACurrentMediaTime(); return;
        }
        if (!arrangementSince || CACurrentMediaTime()-arrangementSince < 0.75) return;
        arrangementSince = 0; // Layout once per membership/orientation/size change, not per drag.
        NFBTile *tiles = calloc(participants.count, sizeof(NFBTile));
        if (!tiles) return;
        for (NSUInteger i=0; i<participants.count; i++) {
            UIView *view=participants[i]; NSDictionary *state=[arrangementStates objectForKey:view];
            CGAffineTransform base=[state[@"base"] CGAffineTransformValue];
            CGRect natural=CGRectApplyAffineTransform((CGRect){CGPointZero,view.bounds.size},base);
            tiles[i].width=natural.size.width; tiles[i].height=natural.size.height;
        }
        // Sorted mini, landscape, portrait: mini forms the top row, landscape is
        // the vertical top group, portrait stays bottom-aligned.
        NSUInteger rowCount = 0, topCount = 0;
        for (UIView *view in participants) {
            NSInteger kind = [[arrangementStates objectForKey:view][@"kind"] integerValue];
            if (kind == 3) rowCount++;
            else if (kind == 2) topCount++;
        }
        if (!NFBArrangeMixed(tiles,participants.count,rowCount,topCount,area.size.height)) { free(tiles); return; }
        NFBPositionLandscape(tiles,participants.count,rowCount,topCount,area.size.height,position);
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled()?0:0.35 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseInOut animations:^{
                for (NSUInteger i=0; i<participants.count; i++) {
                    UIView *view=participants[i]; if (!view.superview) continue;
                    CGRect actual=[view convertRect:view.bounds toCoordinateSpace:screen.coordinateSpace];
                    CGPoint delta=CGPointMake(CGRectGetMinX(area)+tiles[i].x-CGRectGetMinX(actual),CGRectGetMinY(area)+tiles[i].y-CGRectGetMinY(actual));
                    CGPoint p=[view.superview convertPoint:CGPointZero fromCoordinateSpace:screen.coordinateSpace];
                    CGPoint q=[view.superview convertPoint:delta fromCoordinateSpace:screen.coordinateSpace];
                    view.center=CGPointMake(view.center.x+q.x-p.x,view.center.y+q.y-p.y);
                }
            } completion:nil];
        free(tiles);
        NFBDebugLog(@"arrange: windows=%lu landscape=%d portrait=%d",(unsigned long)participants.count,hasLandscape,hasPortrait);
    } @catch (NSException *exception) { NFBDebugLog(@"arrange failed: %@",exception); }
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
        NSMethodSignature *sig = [window methodSignatureForSelector:getter];
        if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return NO;
        id region = ((id (*)(id, SEL))objc_msgSend)(window, getter);
        if (![region isKindOfClass:UIView.class] || ![region isDescendantOfView:window]) {
            NFBDebugLog(@"orange-close: rightTouchRegion unavailable");
            return NO;
        }
        NFBRightEdgeTap *tap = [NFBRightEdgeTap new]; tap.edgeRegion = region;
        BOOL sent = NFBDispatchRightEdgeTap(window, tap);
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
        NSMethodSignature *sig = [window methodSignatureForSelector:getter];
        if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return NO;
        id region = ((id (*)(id, SEL))objc_msgSend)(window, getter);
        if (![region isKindOfClass:UIView.class] || ![region isDescendantOfView:window]) return NO;
        NFBTopLongPress *gesture = [NFBTopLongPress new]; gesture.titleRegion = region;
        BOOL sent = NFBDispatchTopLongPress(window, gesture);
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
            NSMethodSignature *requestSig = [window methodSignatureForSelector:request];
            if (requestSig.numberOfArguments != 3 || strcmp(requestSig.methodReturnType, @encode(void)) ||
                strcmp([requestSig getArgumentTypeAtIndex:2], @encode(NSInteger))) {
                state[@"landscape"] = @NO;
                NFBDebugLog(@"portrait-content: scene request unavailable app=%@", appOfWindow(window));
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
        NSMethodSignature *sig = [window methodSignatureForSelector:layout];
        if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void))) return;
        [UIView performWithoutAnimation:^{
            ((void (*)(id, SEL))objc_msgSend)(window, layout);
            [window setNeedsLayout]; [window layoutIfNeeded];
        }];
        NFBDebugLog(@"portrait-content: reconciled app=%@ bounds=%@", appOfWindow(window), bounds);
    } @catch (NSException *exception) { NFBDebugLog(@"portrait-content: %@", exception); }
}
