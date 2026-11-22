#import "NFBWindowControls.h"
#import "NFBSplitCoordinator.h"
#import "NFBSplitLayout.h"
#import "NFBMovieGeometryPolicy.h"
static BOOL NFBMovieValidLower(CGRect frame, CGRect area) {
    return NFBMovieLowerGeometryValid(frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
        area.origin.x,area.origin.y,area.size.width,area.size.height);
}
#import "NFBSplitObservation.h"
#import "NFBDesktopHost.h"
#import "NFBKeyboard.h"
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
// Rail-only reference. Never populated from the resized desktop proxy.
static CGRect portraitRailReference;
static CGSize portraitRailScreen;
static __weak UIView *portraitRailRoot;
static id currentWindow(void) {
    return NFBCurrentWindowState().floatingWindow;
}
static UIView *attachmentWindow(void);
static CGRect NFBMovieStandardPane(CGRect area) {
    CGFloat height=NFBMoviePaneHeight(area.size.width,area.size.height);
    return CGRectMake(CGRectGetMinX(area),CGRectGetMaxY(area)-height,
        area.size.width*NFBMoviePortraitScale,height);
}
CGRect NFBSplitFrameInView(UIView *root) {
    if (!NSThread.isMainThread || !root.window) return CGRectNull;
    @try {
        id object = attachmentWindow();
        UIView *view = [object isKindOfClass:UIView.class] ? object : nil;
        if (view.window && !view.hidden && !CGRectIsEmpty(view.bounds)) {
            CGRect frame = [view convertRect:view.bounds toView:root];
            // Match the original 0.48.127 input: the real portrait app window.
            if (NFBMovieValidLower(frame, root.bounds)) {
                portraitRailReference = frame;
                portraitRailScreen = root.bounds.size;
                portraitRailRoot = root;

            }
            return frame;
        }
        UIView *manualAnchor = NFBDesktopIndependentAnchor();
        if (manualAnchor.window) return [manualAnchor convertRect:manualAnchor.bounds toView:root];
        if (NFBDesktopSplitActive() && movieDesktopAnchor.window) {
            if (CGSizeEqualToSize(portraitRailScreen, root.bounds.size) &&
                NFBMovieValidLower(portraitRailReference, root.bounds)) return portraitRailReference;
            // No real portrait measured in this session: use the normal Open
            // 0.86 portrait footprint, NOT the movie proxy's reduced footprint.
            CGSize size = root.bounds.size;
            return NFBMovieStandardPane((CGRect){CGPointZero,size});
        }
        return CGRectNull;
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
    return attachmentWindow() ?: NFBDesktopIndependentAnchor() ?: ((movieIsActive && NFBDesktopSplitActive()) ? movieDesktopAnchor : nil);
}
CGRect NFBWindowFrameInView(UIView *window, UIView *root) {
    if (!NSThread.isMainThread || !root.window || !window) return CGRectNull;
    @try { return visibleView(window) ? [window convertRect:window.bounds toView:root] : CGRectNull; }
    @catch (__unused NSException *exception) { return CGRectNull; }
}
NSString *NFBSplitAttachmentApp(void) {
    @try { return appOfWindow(attachmentWindow()) ?: ((NFBDesktopIndependentAnchor() || (movieIsActive && NFBDesktopSplitActive())) ? NFBSystemDesktopBundleID : nil); }
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
            // Open owns portrait geometry while typing. A queued launch retry
            // must not restore 0.86/bottom placement after keyboard adaptation.
            if (NFBKeyboardVisible()) {
                NFBDebugLog(@"placement: deferred %@ while keyboard visible", app);
                return;
            }
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

// Unlike the existing button path, the home swipe never uses a global bridge
// or a direct-close fallback: capability must be proven BEFORE owning the pull.
UIView *NFBHomeSwipeCloseWindow(void) {
    if (!NSThread.isMainThread) return nil;
    @try {
        NFBOpenWindowObservation *observation = NFBCaptureOpenWindows();
        // A bottom swipe is only for portrait panes; the movie X owns the
        // upper close action. Never fall back to a lone landscape window.
        UIView *window = observation.portrait;
        if (!window || ![observation.windows containsObject:window] || [observation.landscapeWindows containsObject:window] ||
            NFBExpandedWindowKind(boolStateOf(window,@"miniWindowModeEnabled"),
                boolStateOf(window,@"isTransitioningFromMiniMode"),
                orientationOf(window,@"sceneOrientation"),orientationOf(window,@"containerOrientation"))!=1) return nil;
        if (!window || !visibleView(window) ||
            boolStateOf(window, @"miniWindowModeEnabled") != 0 ||
            boolStateOf(window, @"isTransitioningFromMiniMode") != 0 ||
            boolStateOf(window, @"isClosingWithKeepAliveAnimation") != 0) return nil;
        NSMethodSignature *signature = NFBSignature(window, NSSelectorFromString(@"handleBottomSingleTap:"));
        if (signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, @encode(void)) ||
            strcmp([signature getArgumentTypeAtIndex:2], @encode(id))) return nil;
        id region = NFBCheckedObject(window, @"rightTouchRegion");
        return [region isKindOfClass:UIView.class] && [region isDescendantOfView:window] ? window : nil;
    } @catch (__unused NSException *error) { return nil; }
}
BOOL NFBCloseHomeSwipeWindow(UIView *window) {
    if (!NSThread.isMainThread || !window) return NO;
    @try {
        NFBInvalidateWindowState();
        if (NFBHomeSwipeCloseWindow() != window) return NO;
        UIView *region = NFBCheckedObject(window, @"rightTouchRegion");
        if (![region isKindOfClass:UIView.class] || ![region isDescendantOfView:window]) return NO;
        NFBRightEdgeTap *tap = [NFBRightEdgeTap new]; tap.edgeRegion = region;
        [NFBSplitCoordinator.shared beginUserWindowOperation];
        BOOL closed = NFBDispatchRightEdgeTap(window, tap);
        if (closed) NFBInvalidateWindowState();
        return closed;
    } @catch (__unused NSException *error) { return NO; }
}

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
@property(nonatomic) CGAffineTransform appliedTransform;
@property(nonatomic) CGPoint appliedCenter;
@property(nonatomic) NSInteger sceneOrientation;
@property(nonatomic) NSInteger containerOrientation;
@property(nonatomic, weak) UIView *parent;

@end
@implementation NFBMovieRecord
@end
static NSMapTable<UIView *, NFBMovieRecord *> *movieRecords;
@interface NFBMovieCutoutLayer : CAShapeLayer
@property(nonatomic) CGRect cachedHole;
@property(nonatomic) CGRect cachedBounds;
@property(nonatomic) CGFloat cachedRadius;
@end
@implementation NFBMovieCutoutLayer
@end
static NSMapTable<UIView *, UIView *> *movieBackdrops;
static CFTimeInterval movieReadAt;
static BOOL movieWasEnabled;
static __weak UIView *moviePortrait;
static BOOL movieOwnsDesktop;
static NSUInteger movieDesktopSession;
static BOOL movieDesktopAttempted;
static BOOL movieDesktopRecoveryUsed;
BOOL NFBMovieOwnsDesktopSession(void) {
    return NSThread.isMainThread && movieIsActive && movieOwnsDesktop &&
        movieDesktopSession!=0 && movieDesktopSession==NFBDesktopSessionIdentifier();
}
static NFBSplitObservationTracker movieObservation;
static NSHashTable<UIView *> *movieLastLandscape;
static BOOL movieHadLandscape;
static CGRect movieLowerScreen;

BOOL NFBCloseMovieUpperWindow(UIView *target) {
    if (!NSThread.isMainThread || !movieIsActive || !target.window) return NO;
    NFBOpenWindowObservation *observation=NFBCaptureOpenWindows();
    if (observation.landscapeWindows.count!=1 || observation.landscapeWindows.firstObject!=target ||
        target==observation.portrait) return NO;
    SEL close=NSSelectorFromString(@"closeWindowWithoutTerminatingProcessWithoutAnimation");
    NSMethodSignature *sig=NFBSignature(target,close);
    if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(void))) return NO;
    @try {
        [NFBSplitCoordinator.shared beginUserWindowOperation];
        ((void (*)(id,SEL))objc_msgSend)(target,close);
        NFBInvalidateWindowState();
        movieReadAt=0;
        if (NFBDebugLoggingEnabled()) {
            NSUInteger epoch=NFBSplitCoordinator.shared.operationEpoch;
            __weak UIView *upper=target;
            __weak UIView *lower=observation.portrait;
            BOOL hadLower=lower!=nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                if (!NFBDebugLoggingEnabled() || NFBSplitCoordinator.shared.operationEpoch!=epoch) return;
                NFBOpenWindowObservation *after=NFBCaptureOpenWindows();
                if (!after.classAvailable || !after.sceneAvailable) return;
                UIView *previousUpper=upper, *previousLower=lower;
                NFBDebugLog(@"movie: upper-close result upperGone=%d hadLower=%d sameLowerVisible=%d",
                    !previousUpper || ![after.windows containsObject:previousUpper], hadLower,
                    previousLower && [after.windows containsObject:previousLower]);
            });
        }
        return YES;
    } @catch (NSException *error) {
        NFBDebugLog(@"movie: exact upper close failed %@",error);
        return NO;
    }
}
BOOL NFBReplaceObservedSplitWithDesktop(UIView *window) {
    if (!movieIsActive) return NFBReplaceSplitWithDesktop(window);
    NFBOpenWindowObservation *observation=NFBCaptureOpenWindows();
    if (!window || window!=observation.portrait || !observation.landscapeWindows.count) return NO;
    NSUInteger retained=NFBMovieOwnsDesktopSession() ? movieDesktopSession : 0;
    UIView *anchor=nil;
    if (!retained) {
        UIView *parent=window.superview;
        if (!parent.window) return NO;
        CGRect area=[parent convertRect:parent.window.bounds fromView:parent.window];
        CGRect pane=NFBMovieStandardPane(area);
        if (!NFBMovieValidLower(pane,area)) return NO;
        anchor=[[UIView alloc] initWithFrame:pane];
        anchor.userInteractionEnabled=NO;
        [parent addSubview:anchor];
    }
    BOOL replaced=NFBReplaceMoviePaneWithAnchor(window, retained, anchor);
    [anchor removeFromSuperview];
    if (!replaced) return NO;
    movieDesktopSession=NFBDesktopSessionIdentifier();
    movieOwnsDesktop=movieDesktopSession!=0;
    movieDesktopAttempted=movieOwnsDesktop;
    if (movieOwnsDesktop && !retained) NFBSetMovieDesktopParked(movieDesktopSession, NO);
    movieReadAt=0;
    NFBDebugLog(@"movie-desktop: house session=%lu reused=%d",(unsigned long)movieDesktopSession,retained!=0);
    return YES;
}
static BOOL movieLandscape(UIView *view) {
    NSInteger a = orientationOf(view, @"sceneOrientation"), b = orientationOf(view, @"containerOrientation");
    return a == 3 || a == 4 || b == 3 || b == 4;
}
CGRect NFBMovieLowerFrameInView(UIView *root) {
    if (!movieIsActive || !root.window || CGRectIsEmpty(movieLowerScreen)) return CGRectNull;
    if (moviePortrait.window) return [moviePortrait convertRect:moviePortrait.bounds toView:root];
    return [root convertRect:movieLowerScreen fromView:movieDesktopAnchor.window];
}
static void movieCollect(UIView *view, Class cls, NSMutableArray<UIView *> *out, NSMutableArray<UIView *> *minis) {
    if (view.hidden || view.alpha < 0.01) return;
    if ([view isKindOfClass:cls]) {
        if (visibleView(view) && appOfWindow(view).length &&
            boolStateOf(view, @"isClosingWithKeepAliveAnimation") != 1) {
            NSInteger mini=boolStateOf(view,@"miniWindowModeEnabled");
            if (mini==0) [out addObject:view];
            else if (mini==1 && boolStateOf(view,@"isTransitioningFromMiniMode")==0) [minis addObject:view];
        }
        return; // Never traverse app content.
    }
    for (UIView *child in view.subviews) movieCollect(child, cls, out, minis);
}
@implementation NFBOpenWindowObservation @end
NFBOpenWindowObservation *NFBCaptureOpenWindows(void) {
    NSCAssert(NSThread.isMainThread,@"Open observations require main queue");
    NFBOpenWindowObservation *observation=[NFBOpenWindowObservation new];
    NSMutableArray<UIView *> *windows=[NSMutableArray array];
    Class cls=NFBTrollFloatingWindowClass();
    NSMutableArray<UIView *> *minis=[NSMutableArray array];
    observation.classAvailable=cls!=Nil;
    if (cls) for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState==UISceneActivationStateBackground ||
            scene.activationState==UISceneActivationStateUnattached) continue;
        observation.sceneAvailable=YES;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) movieCollect(window,cls,windows,minis);
    }
    observation.windows=windows; observation.miniWindows=minis;
    NSMutableArray<UIView *> *landscapes=[NSMutableArray array];
    for (UIView *view in windows) if (movieLandscape(view)) [landscapes addObject:view];
    observation.landscapeWindows=landscapes;
    UIView *portrait=attachmentWindow();
    if ([windows containsObject:portrait] && !movieLandscape(portrait)) observation.portrait=portrait;
    return observation;
}
static void movieRestore(UIView *view) {
    NFBMovieRecord *record = [movieRecords objectForKey:view];
    if (!record) return;
    // Portrait-only records were never moved: do not overwrite Open's latest
    // portrait geometry with a stale value on movie exit.
    // Restore only a geometry we still own. A rotation/reparent or Open's
    // own layout supersedes our saved state; never overwrite that newer state.
    BOOL sameOwner = view.superview == record.parent &&
        orientationOf(view, @"sceneOrientation") == record.sceneOrientation &&
        orientationOf(view, @"containerOrientation") == record.containerOrientation &&
        CGAffineTransformEqualToTransform(view.transform, record.appliedTransform) &&
        CGPointEqualToPoint(view.center, record.appliedCenter);
    if (record.moved && sameOwner) {
        view.transform = record.transform;
        if (view.superview) view.center = record.center;
    }
    [movieRecords removeObjectForKey:view];
}
// Keep native sibling order for both UIKit and the leased host hit-test.
@interface NFBMovieMiniOrder : NSObject
@property(nonatomic,weak) UIView *parent,*next,*upper;
@end
@implementation NFBMovieMiniOrder @end
static NSMapTable<UIView *,NFBMovieMiniOrder *> *miniOrder;
static void NFBReconcileMiniOrder(NSArray<UIView *> *minis, NSArray<UIView *> *uppers) {
    if (!miniOrder) miniOrder=[NSMapTable weakToStrongObjectsMapTable];
    for (UIView *mini in miniOrder.keyEnumerator.allObjects) {
        NFBMovieMiniOrder *r=[miniOrder objectForKey:mini];
        if ([minis containsObject:mini] && [uppers containsObject:r.upper] && mini.superview==r.parent) continue;
        NSArray *siblings=r.parent.subviews;
        NSUInteger index=[siblings indexOfObjectIdenticalTo:r.upper];
        if (mini.superview==r.parent && r.next.superview==r.parent && r.next && index!=NSNotFound &&
            index+1<siblings.count && siblings[index+1]==mini && boolStateOf(mini,@"miniWindowModeEnabled")==1)
            [r.parent insertSubview:mini belowSubview:r.next];
        [miniOrder removeObjectForKey:mini];
    }
    for (UIView *mini in minis) {
        if ([miniOrder objectForKey:mini] || !mini.superview || mini.layer.animationKeys.count) continue;
        UIView *p=mini.superview; NSArray *siblings=p.subviews;
        NSUInteger index=[siblings indexOfObjectIdenticalTo:mini];
        UIView *upper=nil; NSUInteger front=index;
        for (UIView *candidate in uppers) {
            if (candidate.superview!=p || candidate.layer.zPosition!=mini.layer.zPosition || !CGRectIntersectsRect(candidate.frame,mini.frame)) continue;
            NSUInteger i=[siblings indexOfObjectIdenticalTo:candidate];
            if (i!=NSNotFound && i>front) { upper=candidate; front=i; }
        }
        if (!upper || index==NSNotFound || index+1>=siblings.count) continue;
        NFBMovieMiniOrder *r=[NFBMovieMiniOrder new];r.parent=p;r.next=siblings[index+1];r.upper=upper;
        [p insertSubview:mini aboveSubview:upper];
        [miniOrder setObject:r forKey:mini];
    }
}
BOOL NFBUpdateMovieMode(BOOL enabled) {
    if (!NSThread.isMainThread) return NO;
    return NFBApplyMovieObservation(enabled,enabled ? NFBCaptureOpenWindows() : nil);
}
BOOL NFBApplyMovieObservation(BOOL enabled, NFBOpenWindowObservation *observation) {
    if (!NSThread.isMainThread) return NO;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL explicitlyClosed=movieHadLandscape && observation.classAvailable && observation.sceneAvailable &&
        observation.landscapeWindows.count==0;
    if (explicitlyClosed) for (UIView *old in movieLastLandscape.allObjects) {
        if (old.window && boolStateOf(old,@"isClosingWithKeepAliveAnimation")!=1) {
            explicitlyClosed=NO; break; // hiding/rotation/mini must use normal confirmation
        }
    }
    if (!explicitlyClosed && enabled == movieWasEnabled && now - movieReadAt < 0.2) return movieIsActive;
    movieReadAt = now; movieWasEnabled = enabled;
    if (!movieRecords) movieRecords = [NSMapTable weakToStrongObjectsMapTable];
    if (!movieBackdrops) movieBackdrops = [NSMapTable weakToStrongObjectsMapTable];
    NSArray<UIView *> *windows=enabled ? (observation.windows ?: @[]) : @[];
    BOOL sceneAvailable=observation.sceneAvailable;
    BOOL classAvailable=observation.classAvailable;
    BOOL landscape = enabled && observation.landscapeWindows.count>0;
    if (landscape || observation.portrait) NFBUpdateDesktopReturnTransition(NO);
    // While Open rebuilds scenes, no class/window is UNKNOWN rather than closed.
    // Keep existing leases for at most two 0.2s samples; lock/disable releases
    // immediately. Do not run fit or open desktop using an unknown snapshot.
    NFBSplitObservation presence=landscape ? NFBSplitObservationPresent :
        ((!classAvailable || !sceneAvailable) ? NFBSplitObservationUnknown : NFBSplitObservationAbsent);
    BOOL retained=NFBSplitRetainMovieWithClosure(&movieObservation,movieIsActive,enabled,presence,explicitlyClosed);
    if (landscape) {
        movieLastLandscape=[NSHashTable weakObjectsHashTable];
        for (UIView *view in observation.landscapeWindows) [movieLastLandscape addObject:view];
        movieHadLandscape=YES;
    } else if (!retained) {
        movieHadLandscape=NO; [movieLastLandscape removeAllObjects];
    }
    if (explicitlyClosed) NFBDebugLog(@"split-core: confirmed movie close; skip missing-window grace");
    if (enabled && !landscape && retained) {
        NFBDebugLog(@"split-core: movie snapshot temporarily %s; preserving current leases",presence==NFBSplitObservationUnknown?"unknown":"absent");
        return movieIsActive;
    }
    movieIsActive = enabled && landscape;
    moviePortrait = nil;
    // Reuse the same frontmost portrait selection as the rail. Never choose
    // an arbitrary first window from UIWindowScene enumeration order.
    moviePortrait=observation.portrait;
    if (movieIsActive && movieOwnsDesktop && movieDesktopSession==NFBDesktopSessionIdentifier()) {
        NFBSetMovieDesktopParked(movieDesktopSession, moviePortrait != nil);
    }
    if (!movieIsActive) {
        if (movieOwnsDesktop && movieDesktopSession==NFBDesktopSessionIdentifier()) {
            if (enabled && explicitlyClosed) NFBCloseMovieDesktopWithTransition(movieDesktopSession);
            else NFBCloseDesktopSplit();
        }
        movieOwnsDesktop = NO; movieDesktopAttempted = NO; movieDesktopRecoveryUsed = NO;
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
        if (record && (record.parent != parent ||
            record.sceneOrientation != orientationOf(view, @"sceneOrientation") ||
            record.containerOrientation != orientationOf(view, @"containerOrientation"))) {
            // The new orientation/host is already Open-owned. Do not replay old
            // landscape geometry into it. Capture a fresh baseline below.
            [movieRecords removeObjectForKey:view]; record = nil;
        }
        if (!record) {
            record = [NFBMovieRecord new]; record.view = view;
            record.parent = parent;
            record.sceneOrientation = orientationOf(view, @"sceneOrientation");
            record.containerOrientation = orientationOf(view, @"containerOrientation");
            record.center = view.center;
            record.transform = view.transform;
            [movieRecords setObject:record forKey:view];
        }
        // Leave all window and content corner styles owned by Open.
        if ([observation.landscapeWindows containsObject:view]) {
            // Match the standard Open 0.86 portrait's bottom alignment, not a
            // transient portrait sample or an unrelated cached rail footprint.
            // Keep Open in charge of the actual app window (including keyboard).
            CGRect lower=NFBMovieStandardPane(area);
            UIView *manualDesktop = NFBDesktopIndependentAnchor();
            if (manualDesktop.window) {
                CGRect reference=[manualDesktop convertRect:manualDesktop.bounds toView:parent];
                if (NFBMovieValidLower(reference,area)) lower=reference;
            }
            BOOL needsMovieAnchor=!manualDesktop.window;
            if (!NFBMovieValidLower(lower, area)) {
                NFBDebugLog(@"movie: defer invalid lower=%@ area=%@", NSStringFromCGRect(lower), NSStringFromCGRect(area));
                continue;
            }
            if (needsMovieAnchor) {
                if (!movieDesktopAnchor) {
                    movieDesktopAnchor = [UIView new];
                    movieDesktopAnchor.userInteractionEnabled = NO;
                }
                // Reparent before assigning parent-local coordinates.
                if (movieDesktopAnchor.superview != parent) [parent addSubview:movieDesktopAnchor];
                movieDesktopAnchor.frame = lower;
            }
            // Keep the desktop anchor stable. Only video fitting follows the
            // live lower app while Open is adapting it for the keyboard.
            if (NFBKeyboardVisible() && moviePortrait.window) {
                CGRect keyboardLower=[moviePortrait convertRect:moviePortrait.bounds toView:parent];
                if (NFBMovieValidLower(keyboardLower,area)) lower=keyboardLower;
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
            // Bottom-align above the unchanged lower pane with a fixed 4pt gap.
            const CGFloat movieGap = 4.0;
            CGFloat room = MAX(1, CGRectGetMinY(lower)-CGRectGetMinY(area)-movieGap);
            (void)room;
            NFBSplitBasis layoutBasis={basis.a,basis.b,basis.c,basis.d};
            NFBSplitMovieTarget layoutTarget=NFBSplitPlanMovie(area.origin.x,area.origin.y,area.size.width,area.size.height,
                lower.origin.y,lower.size.width,lower.size.height,CGRectGetMaxY(lower),
                view.bounds.size.width,view.bounds.size.height,layoutBasis,movieGap);
            if (!layoutTarget.valid) continue;
            CGFloat ratio=layoutTarget.scale;
            CGAffineTransform destination = CGAffineTransformScale(basis, ratio, ratio);
            CGPoint target = CGPointMake(layoutTarget.x, layoutTarget.y);
            CGAffineTransform current = view.transform;
            BOOL changed = fabs(current.a-destination.a)>0.0001 || fabs(current.b-destination.b)>0.0001 ||
                fabs(current.c-destination.c)>0.0001 || fabs(current.d-destination.d)>0.0001 ||
                fabs(current.tx-destination.tx)>0.01 || fabs(current.ty-destination.ty)>0.01 ||
                fabs(view.center.x-target.x)>0.5 || fabs(view.center.y-target.y)>0.5;
            if (changed) {
                // Model values become the destination immediately. An identical
                // settling recheck does not restart the animation; a changed
                // destination continues from the current presentation state.
                void (^apply)(void) = ^{ view.transform = destination; view.center = target; };
                if (record.moved && !UIAccessibilityIsReduceMotionEnabled()) {
                    [UIView animateWithDuration:0.28 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                            UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
                        animations:apply completion:nil];
                } else [UIView performWithoutAnimation:apply];
                NFBDebugLog(@"movie: target app=%@ center=%@ size=%.1fx%.1f animated=%d",
                    appOfWindow(view), NSStringFromCGPoint(target), w*ratio, h*ratio, record.moved);
                record.moved = YES;
                record.appliedTransform = destination;
                record.appliedCenter = target;
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
    // Rearm only once after losing a previously owned session, and only in
    // a complete observation with no lower app and no replacement desktop.
    if (movieIsActive && classAvailable && sceneAvailable && !moviePortrait &&
        movieOwnsDesktop && movieDesktopSession && !NFBDesktopSessionIdentifier() &&
        !movieDesktopRecoveryUsed && movieDesktopAnchor.window &&
        NFBMovieValidLower(movieDesktopAnchor.frame, movieDesktopAnchor.superview.bounds)) {
        movieDesktopRecoveryUsed=YES;
        movieDesktopAttempted=NO;
        NFBDebugLog(@"movie-desktop: recover lost session=%lu",(unsigned long)movieDesktopSession);
    }
    if (movieIsActive && !moviePortrait && movieDesktopAnchor.window && !movieDesktopAttempted &&
        NFBMovieValidLower(movieDesktopAnchor.frame, movieDesktopAnchor.superview.bounds)) {
        // Geometry is committed before consuming the one-shot attempt. Invalid
        // close-animation samples never create a failed desktop transaction.
        movieDesktopAttempted = YES;
        if (!NFBDesktopSplitActive()) movieOwnsDesktop = NFBShowDesktopInSplit(movieDesktopAnchor);
        movieDesktopSession=movieOwnsDesktop ? NFBDesktopSessionIdentifier() : 0;
        if (movieOwnsDesktop) NFBSetMovieDesktopParked(movieDesktopSession, NO);
        NFBDebugLog(@"movie: desktop fallback active=%d", NFBDesktopSplitActive());
        if (NFBDebugLoggingEnabled()) for (UIView *view in windows) {
            NFBDebugLog(@"movie-touch: floating app=%@ view=%p window=%p class=%@ level=%.1f hidden=%d interaction=%d frame=%@",
                appOfWindow(view), view, view.window, NSStringFromClass(view.window.class),
                view.window.windowLevel, view.hidden, view.userInteractionEnabled, NSStringFromCGRect(view.frame));
        }
    }
    NSMutableArray<UIWindow *> *touchHosts = [NSMutableArray array];
    if (movieIsActive && !NFBMovieDesktopParked() && ((movieOwnsDesktop && movieDesktopSession==NFBDesktopSessionIdentifier()) || NFBDesktopIndependentAnchor()) && NFBDesktopSplitActive()) {
        for (UIView *view in observation.landscapeWindows) if (view.window &&
            ![touchHosts containsObject:view.window]) [touchHosts addObject:view.window];
    }
    // The host is now above the desktop for native touch delivery. Its black
    // backdrop must NOT rise over the hosted desktop pixels. Cut only that pane
    // out of the backdrop; keep the rest pure black and all layers noninteractive.
    UIView *desktopCutout = NFBDesktopIndependentAnchor() ?: movieDesktopAnchor;
    for (UIView *parent in movieBackdrops.keyEnumerator.allObjects) {
        UIView *black = [movieBackdrops objectForKey:parent];
        if ([touchHosts containsObject:parent.window] && desktopCutout.window) {
            CGRect hole = [desktopCutout convertRect:desktopCutout.bounds toView:black];
            // Close the rectangular corner leaks around the rounded desktop.
            // Convert the committed pane radius to this backdrop's coordinates.
            CGFloat radius = NFBDesktopSplitCornerRadius();
            CGFloat scale = hole.size.width / MAX(1, desktopCutout.bounds.size.width);
            if (!isfinite(radius) || radius < 0) radius = 0;
            radius = MIN(radius * scale, MIN(hole.size.width, hole.size.height) / 2);
            NFBMovieCutoutLayer *mask = [black.layer.mask isKindOfClass:NFBMovieCutoutLayer.class]
                ? (NFBMovieCutoutLayer *)black.layer.mask : nil;
            BOOL cutoutChanged = !mask || !CGRectEqualToRect(mask.cachedHole,hole) ||
                !CGRectEqualToRect(mask.cachedBounds,black.bounds) || fabs(mask.cachedRadius-radius)>0.001;
            if (cutoutChanged) {
                if (!mask) mask = [NFBMovieCutoutLayer layer];
                UIBezierPath *path = [UIBezierPath bezierPathWithRect:black.bounds];
                [path appendPath:[UIBezierPath bezierPathWithRoundedRect:hole cornerRadius:radius]];
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                mask.frame = black.bounds; mask.fillRule = kCAFillRuleEvenOdd;
                mask.path = path.CGPath; mask.fillColor = UIColor.blackColor.CGColor;
                mask.cachedHole=hole; mask.cachedBounds=black.bounds; mask.cachedRadius=radius;
                black.layer.mask = mask; [CATransaction commit];
            }
        } else black.layer.mask = nil;
    }
    NFBUpdateMovieDesktopTouchHosts(touchHosts);
    // Publish roots from exactly the observation that produced the geometry and
    // host lease. No hit-time full-window rescan may introduce unrelated views.
    NSArray<UIView *> *minis=movieIsActive ? observation.miniWindows : nil;
    NSMutableArray<UIView *> *uppers=[NSMutableArray array];
    for (UIView *upper in observation.landscapeWindows) if ([active containsObject:upper]) [uppers addObject:upper];
    NFBReconcileMiniOrder(minis,uppers);
    NSMutableArray<UIView *> *touchRoots=[uppers mutableCopy];
    for (UIView *mini in minis) if ([touchHosts containsObject:mini.window]) [touchRoots addObject:mini];
    NFBPublishMovieTouchWindows(touchRoots, NFBDesktopSessionIdentifier());
    for (UIView *view in movieRecords.keyEnumerator.allObjects)
        if (![active containsObject:view]) movieRestore(view);
    for (UIView *parent in movieBackdrops.keyEnumerator.allObjects) if (![parents containsObject:parent]) {
        [[movieBackdrops objectForKey:parent] removeFromSuperview];
        [movieBackdrops removeObjectForKey:parent];
    }
    return movieIsActive && active.count > 0;
}

void NFBRecheckMovieLayout(void) {
    if (!NSThread.isMainThread) return;
    movieReadAt = 0;
    BOOL active = NFBUpdateMovieMode(YES);
    NFBDebugLog(@"movie-keyboard: recheck active=%d lower=%@", active, NSStringFromCGRect(movieLowerScreen));
    if (!NFBDebugLoggingEnabled() || !active) return;
    for (UIView *view in movieRecords.keyEnumerator.allObjects) {
        NFBDebugLog(@"movie-keyboard: app=%@ view=%p window=%p class=%@ level=%.1f frame=%@ interaction=%d",
            appOfWindow(view), view, view.window, NSStringFromClass(view.window.class),
            view.window.windowLevel, NSStringFromCGRect(view.frame), view.userInteractionEnabled);
    }
}

BOOL NFBRecheckMovieDesktopAfterCleanup(NSArray<NSString *> *clearedApps) {
    if (!NSThread.isMainThread) return YES;
    if (NFBDesktopSplitActive()) return YES; // Never toggle an existing desktop.
    NFBOpenWindowObservation *observation=NFBCaptureOpenWindows();
    if (!observation.classAvailable || !observation.sceneAvailable) return NO;
    NSArray<UIView *> *visible=observation.windows;
    BOOL landscape=NO, closingPortrait=NO;
    for (UIView *view in visible) {
        if ([observation.landscapeWindows containsObject:view]) landscape=YES;
        else if ([clearedApps containsObject:appOfWindow(view)]) closingPortrait=YES;
        else {
            NFBDebugLog(@"movie-cleanup: cancelled for lower app %@",appOfWindow(view));
            return YES; // New/protected lower app wins. Never close it.
        }
    }
    if (!landscape) return YES;
    if (closingPortrait) return NO;
    // A failed earlier one-shot attempt must not permanently suppress this
    // explicit post-cleanup fallback. Only the bounded caller re-arms it.
    movieDesktopAttempted=NO; movieReadAt=0;
    NFBApplyMovieObservation(YES,observation);
    BOOL done=NFBDesktopSplitActive();
    NFBDebugLog(@"movie-cleanup: desktop fallback active=%d",done);
    return done;
}
