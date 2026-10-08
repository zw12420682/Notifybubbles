#import "NFBOpenEdge.h"
#import "NFBWindowControls.h"
#import "NFBPrivate.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <string.h>

// Verified against the supplied Open 1.3.7 binary. Never alter its preferences,
// minimized-app list, notification records or private gesture action pointers.
static BOOL enabledByOwner;
static BOOL splitIconsVisible;
static BOOL installed;
static BOOL lastSuppressed;
static BOOL lastTucked;
static void (*originalSetTucked)(id, SEL, BOOL, BOOL);
static void (*originalSetTuckedPlain)(id, SEL, BOOL);
static BOOL (*originalGetTucked)(id, SEL);
static CGFloat (*originalCenterX)(id, SEL, CGRect, BOOL);
static NSHashTable *owners;
static BOOL (*originalShouldShow)(id, SEL);
static void (*originalRefresh)(id, SEL);
static void (*originalShowEdge)(id, SEL, BOOL);
static void (*originalShowTray)(id, SEL);
// Tucking is Open's native edge position (the position revealed by swiping),
// independent of hiding the button. A visible floating/mini window is not fullscreen.
static BOOL shouldTuck(void) {
    id sb = UIApplication.sharedApplication;
    if ([sb respondsToSelector:@selector(isShowingHomescreen)] && [sb isShowingHomescreen]) return NO;
    // The bridge also reports windows that are not attached to a window scene.
    id floating = NFBGet(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
    if ([floating isKindOfClass:UIView.class] && ![(UIView *)floating isHidden] &&
        [(UIView *)floating alpha] > 0.01) return NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([window isKindOfClass:NSClassFromString(@"FloatingAppWindow")] &&
                !window.hidden && window.alpha > 0.01) return NO;
        }
    }
    return NFBString(NFBGet(NFBGet(sb, @"_accessibilityFrontMostApplication"), @"bundleIdentifier")).length > 0;
}
static BOOL suppressed(void) {
    return enabledByOwner && splitIconsVisible && NSThread.isMainThread;
}
static BOOL tuckValue(BOOL requested) {
    return enabledByOwner && NSThread.isMainThread ? shouldTuck() : requested;
}
static BOOL getTucked(id owner, SEL cmd) {
    return tuckValue(originalGetTucked(owner, cmd));
}
static CGFloat centerX(id owner, SEL cmd, CGRect bounds, BOOL tucked) {
    // Use Open's own left/right geometry, but enforce the presentation policy
    // at the point where the actual on-screen position is calculated.
    return originalCenterX(owner, cmd, bounds, tuckValue(tucked));
}
static void setTucked(id owner, SEL cmd, BOOL tucked, BOOL animated) {
    originalSetTucked(owner, cmd, tuckValue(tucked), animated);
}
static void setTuckedPlain(id owner, SEL cmd, BOOL tucked) {
    originalSetTuckedPlain(owner, cmd, tuckValue(tucked));
}
static void applyTuck(id owner, BOOL animated) {
    if (!enabledByOwner || suppressed()) return;
    originalSetTucked(owner, NSSelectorFromString(@"setEdgeButtonAutoHidden:animated:"), shouldTuck(), animated);
    // The native setter may return early when its stored value is unchanged.
    // Re-run native layout so an old tucked frame cannot survive that branch.
    id button = NFBGet(owner, @"edgeButton");
    if (![button isKindOfClass:UIView.class]) return;
    UIView *host = [(UIView *)button superview];
    if (!host || NFBGet(owner, @"trayBackdrop")) return;
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(owner,
        NSSelectorFromString(@"updateEdgeButtonLayoutInHostView:animated:"), host, animated);
}
static void remember(id owner) {
    if (NSThread.isMainThread) [owners addObject:owner];
}
static BOOL shouldShow(id owner, SEL cmd) {
    remember(owner);
    return suppressed() ? NO : originalShouldShow(owner, cmd);
}
static void refresh(id owner, SEL cmd) {
    remember(owner);
    originalRefresh(owner, cmd);
    applyTuck(owner, YES);
}
static void showEdge(id owner, SEL cmd, BOOL animated) {
    remember(owner);
    if (suppressed()) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(owner, NSSelectorFromString(@"hideEdgeButtonAnimated:"), animated);
        return;
    }
    originalShowEdge(owner, cmd, animated);
    applyTuck(owner, animated);
}
static void showTray(id owner, SEL cmd) {
    remember(owner);
    if (!suppressed()) originalShowTray(owner, cmd);
}
// Native hide completion writes hidden=YES even when its animation was interrupted.
// Reconcile after transitions, retaining the native eligibility/settings decision.
static NSUInteger restoreGeneration;
static void reconcile(void) {
    if (!installed || suppressed()) return;
    for (id owner in owners.allObjects) {
        originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
        applyTuck(owner, NO);
        BOOL allowed = originalShouldShow(owner, NSSelectorFromString(@"shouldShowEdgeIcon"));
        SEL getter = NSSelectorFromString(@"edgeButton");
        NSMethodSignature *sig = [owner methodSignatureForSelector:getter];
        if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') continue;
        UIView *button = ((id (*)(id, SEL))objc_msgSend)(owner, getter);
        if (![button isKindOfClass:UIView.class]) continue;
        // Do not expose the button behind an intentionally open tray.
        SEL trayGetter = NSSelectorFromString(@"trayBackdrop");
        NSMethodSignature *traySig = [owner methodSignatureForSelector:trayGetter];
        if (!traySig || traySig.numberOfArguments != 2 || traySig.methodReturnType[0] != '@') continue;
        id tray = ((id (*)(id, SEL))objc_msgSend)(owner, trayGetter);
        if (allowed && !tray && (button.hidden || button.alpha < 0.01))
            originalShowEdge(owner, NSSelectorFromString(@"showEdgeButtonAnimated:"), NO);
        applyTuck(owner, NO);
        NFBDebugLog(@"Open edge restore: eligible=%d hidden=%d alpha=%.2f owners=%lu",
            allowed, button.hidden, button.alpha, (unsigned long)owners.count);
    }
}
void NFBOpenEdgeAfterClose(void) {
    if (!NSThread.isMainThread) return;
    NSUInteger generation = ++restoreGeneration;
    // Bounded retries cover scene removal, hide completion and late edge registration.
    for (NSNumber *delay in @[@0.15, @0.45, @0.9, @1.5, @2.2]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (generation == restoreGeneration) reconcile();
            });
    }
}
static BOOL matches(Class cls, NSString *name, const char *result, const char *argument) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(sig.methodReturnType, result) || sig.numberOfArguments != (argument ? 3u : 2u)) return NO;
    return !argument || !strcmp([sig getArgumentTypeAtIndex:2], argument);
}
static BOOL matchesPair(Class cls, NSString *name, const char *result,
                        const char *first, const char *second) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return sig.numberOfArguments == 4 && !strcmp(sig.methodReturnType, result) &&
        !strcmp([sig getArgumentTypeAtIndex:2], first) &&
        !strcmp([sig getArgumentTypeAtIndex:3], second);
}
// Apply the current suppression state, restoring the native edge icon when the
// split bubbles leave the screen.
static void applySuppression(void) {
    if (!installed) return;
    BOOL now = suppressed();
    BOOL tucked = shouldTuck();
    if (now == lastSuppressed && tucked == lastTucked) return;
    lastSuppressed = now;
    lastTucked = tucked;
    if (now) ++restoreGeneration;
    else NFBOpenEdgeAfterClose();
    for (id owner in owners.allObjects) {
        originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
        applyTuck(owner, YES);
    }
    // On restoration, native shouldShowEdgeIcon still checks the user's own settings.
    NFBDebugLog(@"Open edge policy: splitIconsHidden=%d tucked=%d owners=%lu", now, tucked, (unsigned long)owners.count);
}
void NFBUpdateOpenEdge(BOOL enabled) {
    if (!NSThread.isMainThread) return;
    enabledByOwner = enabled;
    if (!installed) {
        Class cls = NSClassFromString(@"HIOHODYUSF");
        // All signatures must match before installing any interception.
        if (!cls || !matches(cls, @"shouldShowEdgeIcon", @encode(BOOL), NULL) ||
            !matches(cls, @"refreshUI", @encode(void), NULL) ||
            !matches(cls, @"showEdgeButtonAnimated:", @encode(void), @encode(BOOL)) ||
            !matches(cls, @"hideEdgeButtonAnimated:", @encode(void), @encode(BOOL)) ||
            !matches(cls, @"showTray", @encode(void), NULL)) return;
        if (!matches(cls, @"setEdgeButtonAutoHidden:", @encode(void), @encode(BOOL))) return;
        if (!matches(cls, @"edgeButtonAutoHidden", @encode(BOOL), NULL) ||
            !matchesPair(cls, @"edgeCenterXForHostBounds:tucked:", @encode(CGFloat), @encode(CGRect), @encode(BOOL)) ||
            !matchesPair(cls, @"updateEdgeButtonLayoutInHostView:animated:", @encode(void), @encode(id), @encode(BOOL))) {
            NFBDebugLog(@"Open edge position integration: incompatible method signatures");
            return;
        }
        Method tuckMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"setEdgeButtonAutoHidden:animated:"));
        if (!tuckMethod) return;
        NSMethodSignature *tuckSig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(tuckMethod)];
        if (strcmp(tuckSig.methodReturnType, @encode(void)) || tuckSig.numberOfArguments != 4 ||
            strcmp([tuckSig getArgumentTypeAtIndex:2], @encode(BOOL)) ||
            strcmp([tuckSig getArgumentTypeAtIndex:3], @encode(BOOL))) return;
        owners = [NSHashTable weakObjectsHashTable];
        MSHookMessageEx(cls, NSSelectorFromString(@"edgeButtonAutoHidden"), (IMP)getTucked, (IMP *)&originalGetTucked);
        MSHookMessageEx(cls, NSSelectorFromString(@"edgeCenterXForHostBounds:tucked:"), (IMP)centerX, (IMP *)&originalCenterX);
        MSHookMessageEx(cls, NSSelectorFromString(@"setEdgeButtonAutoHidden:animated:"), (IMP)setTucked, (IMP *)&originalSetTucked);
        MSHookMessageEx(cls, NSSelectorFromString(@"setEdgeButtonAutoHidden:"), (IMP)setTuckedPlain, (IMP *)&originalSetTuckedPlain);
        MSHookMessageEx(cls, NSSelectorFromString(@"shouldShowEdgeIcon"), (IMP)shouldShow, (IMP *)&originalShouldShow);
        MSHookMessageEx(cls, NSSelectorFromString(@"refreshUI"), (IMP)refresh, (IMP *)&originalRefresh);
        MSHookMessageEx(cls, NSSelectorFromString(@"showEdgeButtonAnimated:"), (IMP)showEdge, (IMP *)&originalShowEdge);
        MSHookMessageEx(cls, NSSelectorFromString(@"showTray"), (IMP)showTray, (IMP *)&originalShowTray);
        installed = YES;
        NFBDebugLog(@"Open 1.3.7 edge integration installed");
    }
    applySuppression();
}
// NotifyBubbles tracks when its split bubbles are actually on screen; the edge
// icon is hidden for exactly that window and restored for every other state.
void NFBUpdateOpenEdgeSplitIconsVisible(BOOL visible) {
    if (!NSThread.isMainThread || splitIconsVisible == visible) return;
    splitIconsVisible = visible;
    applySuppression();
}
