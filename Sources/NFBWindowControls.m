#import "NFBWindowControls.h"
#import "NFBDesktopHost.h"
#import "NFBSystemDesktop.h"
#import "NFBTrollOpen.h"
#import "NFBWindowState.h"
#import "NFBInterfaces.h"
#import "NFBRightEdgeAction.h"
#import "NFBWindowKind.h"
#import "NFBSplitClosePolicy.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <string.h>

static __weak UIView *lastWindow;
static NSString *lastApp;
static NSUInteger placementGeneration;
static UIView *movieDesktopAnchor;
static BOOL movieIsActive;
static id currentWindow(void) {
    return NFBCurrentWindowState().floatingWindow;
}
static UIView *attachmentWindow(void);
CGRect NFBSplitFrameInView(UIView *root) {
    if (!NSThread.isMainThread || !root.window) return CGRectNull;
    @try {
        id object = attachmentWindow();
        if (![object isKindOfClass:UIView.class] && !(movieIsActive && NFBDesktopSplitActive())) return CGRectNull;
        UIView *view = [object isKindOfClass:UIView.class] ? object : nil;
        if (!view && movieIsActive && NFBDesktopSplitActive()) view = movieDesktopAnchor;
        if (!view.window || view.hidden || CGRectIsEmpty(view.bounds)) return CGRectNull;
        return [view convertRect:view.bounds toView:root];
    } @catch (__unused NSException *exception) { return CGRectNull; }
}
// The class the attachment lookup depends on is still missing (nil, not merely
// "no window"): a probe taken now answered "nothing" for the wrong reason.
BOOL NFBSplitFrameClassUnavailable(void) {
    return NFBTrollFloatingWindowClass() == Nil;
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
static UIView *floatingInTree(UIView *view, Class floatingClass) {
    if (view.hidden || view.alpha < 0.01) return nil;
    // A floating window is a candidate as a whole; its app content need not be scanned.
    if ([view isKindOfClass:floatingClass]) {
        if (!visibleView(view) || !appOfWindow(view).length ||
            boolStateOf(view, @"isClosingWithKeepAliveAnimation") == 1) return nil;
        NSInteger kind = NFBExpandedWindowKind(boolStateOf(view, @"miniWindowModeEnabled"),
            boolStateOf(view, @"isTransitioningFromMiniMode"),
            orientationOf(view, @"sceneOrientation"), orientationOf(view, @"containerOrientation"));
        return kind == 1 ? view : nil;
    }
    // zPosition overrides subview order; reversed stable order breaks ties.
    NSArray<UIView *> *frontFirst = [[view.subviews reverseObjectEnumerator].allObjects
        sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            if (a.layer.zPosition > b.layer.zPosition) return NSOrderedAscending;
            if (a.layer.zPosition < b.layer.zPosition) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    for (UIView *child in frontFirst) {
        UIView *found = floatingInTree(child, floatingClass);
        if (found) return found;
    }
    return nil;
}
static UIView *frontmostPortraitWindow(void) {
    if (!NSThread.isMainThread) return nil;
    // Identity-based invalidation never hit (the snapshot is rebuilt every
    // runloop turn), so the recursive window-tree scan below ran on every poll.
    // Hold the answer briefly instead; explicit user actions still invalidate.
    static __weak UIView *portrait;
    static BOOL portraitRead;
    static CFTimeInterval readAt;
    CFTimeInterval now = CACurrentMediaTime();
    if (portraitRead && now - readAt > 0.2) { portraitRead = NO; portrait = nil; }
    if (portraitRead) return portrait;
    portraitRead = YES; readAt = now;
    @try {
        Class floatingClass = NFBTrollFloatingWindowClass();
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
            UIView *candidate = floatingInTree(window, floatingClass);
            if (candidate) { portrait = candidate; return candidate; }
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
        return frontmostPortraitWindow();
    } @catch (NSException *exception) { NFBDebugLog(@"attachment lookup: %@", exception); return nil; }
}
UIView *NFBDesktopActionWindow(void) {
    return attachmentWindow() ?: ((movieIsActive && NFBDesktopSplitActive()) ? movieDesktopAnchor : nil);
}
CGRect NFBWindowFrameInView(UIView *window, UIView *root) {
    if (!NSThread.isMainThread || !root.window || !window) return CGRectNull;
    @try { return visibleView(window) ? [window convertRect:window.bounds toView:root] : CGRectNull; }
    @catch (__unused NSException *exception) { return CGRectNull; }
}
NSString *NFBSplitAttachmentApp(void) {
    @try { return appOfWindow(attachmentWindow()) ?: ((movieIsActive && NFBDesktopSplitActive()) ? NFBSystemDesktopBundleID : nil); }
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

static double visualScale(UIView *window) {
    SEL getter = NSSelectorFromString(@"visualScale");
    if (!window || ![window respondsToSelector:getter]) return NAN;
    NSMethodSignature *sig = NFBSignature(window, getter);
    if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(double))) return NAN;
    @try { return ((double (*)(id, SEL))objc_msgSend)(window, getter); }
    @catch (__unused NSException *exception) { return NAN; }
}
static NSTimeInterval NFBPlacementWindow(void) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SplitPlacementWindow"),
        CFSTR("local.notifybubbles")));
    double seconds = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.35;
    if (!isfinite(seconds)) seconds = 0.35;
    if (seconds < 0) seconds = 0;
    if (seconds > 1.0) seconds = 1.0;
    return seconds;
}
// One correction every step; at least one retry is scheduled inside any window.
static const NSTimeInterval NFBPlacementStep = 0.1;
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
        // Apply the placement immediately: the window should already be in its
        // final position when it appears, not after a visible jump. TrollOpen may
        // still be laying out, so the same pass is repeated a few times shortly
        // after; the repeats are bounded and stop as soon as the target holds.
        // The user sets how long corrections may keep running. The first pass is
        // always immediate; later ones follow every NFBPlacementStep seconds up to
        // that window, so any duration between 0 and 1s is covered without steps.
        NSTimeInterval window = NFBPlacementWindow();
        for (NSTimeInterval delay = 0;; delay += NFBPlacementStep) {
        if (delay > window + 0.0001) break;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
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
                // 2.0.1 renamed/replaced this entry point, so downgrade to a plain
                // layout pass instead of dropping the whole placement.
                SEL sync = NSSelectorFromString(@"syncContainerFrameToVisualScalePreservingCenter:");
                NSMethodSignature *syncSig = NFBSignature(window, sync);
                BOOL canSync = syncSig && syncSig.numberOfArguments == 3 &&
                    strcmp(syncSig.methodReturnType, @encode(void)) == 0 &&
                    strcmp([syncSig getArgumentTypeAtIndex:2], @encode(BOOL)) == 0;
                // Idempotent: only ask for the scale when it differs, so a retry
                // does not restart TrollOpen's own resize animation.
                BOOL alreadyScaled = fabs(visualScale(window) - 0.86) < 0.005;
                if (!alreadyScaled) ((void (*)(id, SEL, double))objc_msgSend)(window, scale, 0.86);
                if (canSync) ((void (*)(id, SEL, BOOL))objc_msgSend)(window, sync, YES);
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
        }
    } @catch (NSException *exception) { NFBDebugLog(@"placement lookup: %@", exception); }
}

// Re-apply the split placement once the keyboard has gone: the dismissal can
// change the available area, and the window must end up at the same spot.
void NFBRecheckSplitPlacement(void) {
    if (!NSThread.isMainThread) return;
    NSString *app = NFBTrollVisibleApp();
    if (!app.length) return;
    lastApp = nil; lastWindow = nil;
    NFBObserveSplitPlacement(app);
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
        // 1.3.7: reproduce the native right-region single tap, which is the exact
        // path the user's finger would take.
        SEL tapAction = NSSelectorFromString(@"handleBottomSingleTap:");
        if ([window respondsToSelector:tapAction]) {
            SEL getter = NSSelectorFromString(@"rightTouchRegion");
            NSMethodSignature *sig = NFBSignature(window, getter);
            if (sig.numberOfArguments == 2 && sig.methodReturnType[0] == '@') {
                id region = ((id (*)(id, SEL))objc_msgSend)(window, getter);
                if ([region isKindOfClass:UIView.class] && [region isDescendantOfView:window]) {
                    NFBRightEdgeTap *tap = [NFBRightEdgeTap new]; tap.edgeRegion = region;
                    if (NFBDispatchRightEdgeTap(window, tap)) {
                        NFBInvalidateWindowState();
                        NFBDebugLog(@"orange-close: right-region tap app=%@", appOfWindow(window));
                        return YES;
                    }
                }
            }
            NFBErrorLog(@"orange-close: right-region tap failed");
        }
        // 2.0.1 removed handleBottomSingleTap:; close through the direct entry
        // point instead. It lives on the bridge metaclass, with an instance-method
        // fallback for builds that carry it on the window.
        SEL close = NSSelectorFromString(@"closeCurrentFloatingWindow");
        Class bridge = NSClassFromString(@"TOJBBarGestureBridge");
        id targets[] = {bridge, window};
        for (NSUInteger i = 0; i < 2; i++) {
            id target = targets[i];
            if (!target || ![target respondsToSelector:close]) continue;
            NSMethodSignature *sig = NFBSignature(target, close);
            if (!sig || sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, @encode(void)) != 0) continue;
            ((void (*)(id, SEL))objc_msgSend)(target, close);
            NFBInvalidateWindowState();
            NFBDebugLog(@"orange-close: closeCurrentFloatingWindow on %@", i ? @"window" : @"bridge");
            return YES;
        }
        // Last resort: both editions keep this on the floating window; it closes
        // the pane without terminating the hosted app.
        SEL dismiss = NSSelectorFromString(@"closeWindowWithoutTerminatingProcessWithoutAnimation");
        if ([window respondsToSelector:dismiss]) {
            NSMethodSignature *sig = NFBSignature(window, dismiss);
            if (sig && sig.numberOfArguments == 2 && strcmp(sig.methodReturnType, @encode(void)) == 0) {
                ((void (*)(id, SEL))objc_msgSend)(window, dismiss);
                NFBInvalidateWindowState();
                NFBDebugLog(@"orange-close: closeWindowWithoutTerminatingProcessWithoutAnimation");
                return YES;
            }
        }
        NFBErrorLog(@"orange-close: no close entry point on this TrollOpen build");
        return NO;
    } @catch (NSException *exception) { NFBDebugLog(@"orange-close: %@", exception); return NO; }
}



// Movie layout is opt-in and never changes app lifecycle or orientation.
// Open already rotates its scene; only the rendered window is repositioned.
@interface NFBMovieRecord : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic) CGPoint center;
@property(nonatomic) BOOL moved;
@property(nonatomic) CGAffineTransform transform;
@end
@implementation NFBMovieRecord
@end
static NSMapTable<UIView *, NFBMovieRecord *> *movieRecords;
static NSMapTable<UIView *, UIView *> *movieBackdrops;
static CFTimeInterval movieReadAt;
static BOOL movieWasEnabled;
static __weak UIView *moviePortrait;
static BOOL movieOwnsDesktop;
static BOOL movieDesktopAttempted;
static CGRect movieLowerScreen;
static BOOL movieLandscape(UIView *view) {
    NSInteger a = orientationOf(view, @"sceneOrientation"), b = orientationOf(view, @"containerOrientation");
    return a == 3 || a == 4 || b == 3 || b == 4;
}
CGRect NFBMovieLowerFrameInView(UIView *root) {
    if (!movieIsActive || !root.window || CGRectIsEmpty(movieLowerScreen)) return CGRectNull;
    if (moviePortrait.window) return [moviePortrait convertRect:moviePortrait.bounds toView:root];
    return [root convertRect:movieLowerScreen fromView:movieDesktopAnchor.window];
}
static void movieCollect(UIView *view, Class cls, NSMutableArray<UIView *> *out) {
    if (view.hidden || view.alpha < 0.01) return;
    if ([view isKindOfClass:cls]) {
        if (visibleView(view) && appOfWindow(view).length &&
            boolStateOf(view, @"miniWindowModeEnabled") == 0 &&
            boolStateOf(view, @"isClosingWithKeepAliveAnimation") != 1) [out addObject:view];
        return; // Never traverse app content.
    }
    for (UIView *child in view.subviews) movieCollect(child, cls, out);
}
static void movieRestore(UIView *view) {
    NFBMovieRecord *record = [movieRecords objectForKey:view];
    if (!record) return;
    // Portrait-only records were never moved: do not overwrite Open's latest
    // portrait geometry with a stale value on movie exit.
    if (record.moved) {
        view.transform = record.transform;
        if (view.superview) view.center = record.center;
    }
    [movieRecords removeObjectForKey:view];
}
BOOL NFBUpdateMovieMode(BOOL enabled) {
    if (!NSThread.isMainThread) return NO;
    CFTimeInterval now = CACurrentMediaTime();
    if (enabled == movieWasEnabled && now - movieReadAt < 0.2) return movieIsActive;
    movieReadAt = now; movieWasEnabled = enabled;
    if (!movieRecords) movieRecords = [NSMapTable weakToStrongObjectsMapTable];
    if (!movieBackdrops) movieBackdrops = [NSMapTable weakToStrongObjectsMapTable];
    NSMutableArray<UIView *> *windows = [NSMutableArray array];
    Class cls = NFBTrollFloatingWindowClass();
    if (enabled && cls) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState == UISceneActivationStateBackground ||
                scene.activationState == UISceneActivationStateUnattached) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) movieCollect(window, cls, windows);
        }
    }
    BOOL landscape = NO;
    for (UIView *view in windows) {
        NSInteger orientation = orientationOf(view, @"sceneOrientation");
        NSInteger container = orientationOf(view, @"containerOrientation");
        if (orientation == 3 || orientation == 4 || container == 3 || container == 4) landscape = YES;
    }
    // A normal portrait-only split remains untouched, even with the option on.
    movieIsActive = enabled && landscape;
    moviePortrait = nil;
    for (UIView *view in windows) if (!movieLandscape(view)) { moviePortrait = view; break; }
    if (moviePortrait) {
        if (movieOwnsDesktop && NFBDesktopSplitActive()) NFBCloseDesktopSplit();
        movieOwnsDesktop = NO; movieDesktopAttempted = NO;
        [movieDesktopAnchor removeFromSuperview]; movieDesktopAnchor = nil;
    }
    if (!movieIsActive) {
        if (movieOwnsDesktop && NFBDesktopSplitActive()) NFBCloseDesktopSplit();
        movieOwnsDesktop = NO; movieDesktopAttempted = NO;
        [movieDesktopAnchor removeFromSuperview]; movieDesktopAnchor = nil;
        movieLowerScreen = CGRectZero;
    }
    NSHashTable *active = [NSHashTable weakObjectsHashTable];
    NSHashTable *parents = [NSHashTable weakObjectsHashTable];
    if (movieIsActive) for (UIView *view in windows) {
        UIView *parent = view.superview;
        if (!parent || !parent.window) continue;
        CGRect area = [parent convertRect:parent.window.bounds fromView:parent.window];
        // This mode is for a portrait phone containing a landscape scene.
        if (area.size.width >= area.size.height) continue;
        [active addObject:view]; [parents addObject:parent];
        NFBMovieRecord *record = [movieRecords objectForKey:view];
        if (!record) {
            record = [NFBMovieRecord new]; record.view = view;
            record.center = view.center;
            record.transform = view.transform;
            [movieRecords setObject:record forKey:view];
        }
        // Leave all window and content corner styles owned by Open.
        if (!movieLandscape(view) && record.moved) {
            view.transform = record.transform; view.center = record.center; record.moved = NO;
        }
        NSInteger orientation = orientationOf(view, @"sceneOrientation");
        NSInteger container = orientationOf(view, @"containerOrientation");
        if (orientation == 3 || orientation == 4 || container == 3 || container == 4) {
            // The lower app remains fixed. Top alignment may use the status-bar
            // band; shrink uniformly only if the existing video cannot fit.
            CGRect lower = moviePortrait ? [moviePortrait convertRect:moviePortrait.bounds toView:parent] : CGRectZero;
            if (CGRectIsEmpty(lower)) {
                CGFloat width = area.size.width * 0.86;
                // Use the actual width-derived desktop scale. Reserve a full
                // landscape-video band instead of letting desktop claim 86% height.
                CGFloat videoBand = area.size.width * 9.0 / 16.0;
                CGFloat height = MIN(area.size.height * 0.86, area.size.height-videoBand-2);
                width = height * area.size.width / area.size.height;
                lower = CGRectMake(CGRectGetMinX(area), CGRectGetMaxY(area)-height, width, height);
                if (!movieDesktopAnchor) {
                    movieDesktopAnchor = [UIView new];
                    movieDesktopAnchor.userInteractionEnabled = NO;
                    [parent addSubview:movieDesktopAnchor];
                }
                movieDesktopAnchor.frame = lower;
            }
            movieLowerScreen = [parent convertRect:lower toView:parent.window];
            // Open may rewrite bounds while preserving our transform. Never
            // multiply another fit onto that scale: derive an absolute fit from
            // a rotation-only transform and the CURRENT bounds every pass.
            CGAffineTransform basis = view.transform;
            CGFloat sx = hypot(basis.a, basis.b), sy = hypot(basis.c, basis.d);
            if (sx > 0.0001 && sy > 0.0001) {
                basis.a /= sx; basis.b /= sx; basis.c /= sy; basis.d /= sy;
            } else basis = CGAffineTransformIdentity;
            basis.tx = 0; basis.ty = 0;
            CGFloat w = fabs(basis.a)*view.bounds.size.width + fabs(basis.c)*view.bounds.size.height;
            CGFloat h = fabs(basis.b)*view.bounds.size.width + fabs(basis.d)*view.bounds.size.height;
            CGFloat room = MAX(1, CGRectGetMinY(lower)-CGRectGetMinY(area)-2);
            CGFloat ratio = MIN(room/MAX(1,h), area.size.width/MAX(1,w));
            if (isfinite(ratio) && ratio > 0) {
                view.transform = CGAffineTransformScale(basis, ratio, ratio);
                record.moved = YES;
            }
            CGRect frame = view.frame;
            if (!CGRectIsEmpty(frame) && isfinite(frame.origin.x) && isfinite(frame.origin.y)) {
                CGPoint target = view.center;
                target.x += CGRectGetMidX(area) - CGRectGetMidX(frame);
                target.y += CGRectGetMinY(area) - CGRectGetMinY(frame);
                if (fabs(target.x-view.center.x) > 0.5 || fabs(target.y-view.center.y) > 0.5) {
                    view.center = target; record.moved = YES;
                    NFBDebugLog(@"movie: top placement %@ frame=%@", appOfWindow(view), NSStringFromCGRect(view.frame));
                }
            }
        }
        UIView *black = [movieBackdrops objectForKey:parent];
        if (!black) {
            black = [UIView new]; black.backgroundColor = UIColor.blackColor;
            black.userInteractionEnabled = NO; black.accessibilityElementsHidden = YES;
            [movieBackdrops setObject:black forKey:parent];
        }
        black.frame = area;
        // Insert behind the lowest floating sibling, never above another app.
        UIView *lowest = nil;
        for (UIView *child in parent.subviews) if ([windows containsObject:child]) { lowest = child; break; }
        if (lowest) [parent insertSubview:black belowSubview:lowest];
    }
    if (movieIsActive && !moviePortrait && movieDesktopAnchor.window && !movieDesktopAttempted) {
        movieDesktopAttempted = YES;
        if (!NFBDesktopSplitActive()) movieOwnsDesktop = NFBShowDesktopInSplit(movieDesktopAnchor);
        NFBDebugLog(@"movie: desktop fallback active=%d", NFBDesktopSplitActive());
    }
    for (UIView *view in movieRecords.keyEnumerator.allObjects)
        if (![active containsObject:view]) movieRestore(view);
    for (UIView *parent in movieBackdrops.keyEnumerator.allObjects) if (![parents containsObject:parent]) {
        [[movieBackdrops objectForKey:parent] removeFromSuperview];
        [movieBackdrops removeObjectForKey:parent];
    }
    return movieIsActive && active.count > 0;
}
