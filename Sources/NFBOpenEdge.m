#import "NFBOpenEdge.h"
#import "NFBWindowControls.h"
#import "NFBPrivate.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
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
static BOOL lastFullscreen;
static BOOL lastEnabled;
static BOOL applyingPresentation;
static CFTimeInterval trayDismissUntil;
static void (*originalHideTray)(id, SEL, BOOL);
static NSHashTable *owners;
static BOOL (*originalShouldShow)(id, SEL);
static void (*originalRefresh)(id, SEL);
static void (*originalShowEdge)(id, SEL, BOOL);
static void (*originalShowTray)(id, SEL);
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
    // Hide Open's edge icon only while NotifyBubbles' split bubbles are on screen.
    // Expansion means the native tray (delete/collapse/app icons), not the
    // horizontal position of a single edge button.
    return enabledByOwner && splitIconsVisible && NSThread.isMainThread;
}
// All panel content and gestures remain owned by Open. Reentrancy is possible:
// showing/hiding its tray can call the intercepted edge/refresh methods.
static void applyPresentation(id owner, BOOL animated) {
    if (applyingPresentation || !enabledByOwner || !NSThread.isMainThread) return;
    applyingPresentation = YES;
    @try {
        if (suppressed()) {
            if (NFBGet(owner, @"trayBackdrop"))
                originalHideTray(owner, NSSelectorFromString(@"hideTrayAnimated:"), NO);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(owner,
                NSSelectorFromString(@"hideEdgeButtonAnimated:"), animated);
            return;
        }
        if (!originalShouldShow(owner, NSSelectorFromString(@"shouldShowEdgeIcon"))) return;
        if (shouldTuck()) {
            if (NFBGet(owner, @"trayBackdrop"))
                originalHideTray(owner, NSSelectorFromString(@"hideTrayAnimated:"), NO);
            ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(owner,
                NSSelectorFromString(@"setEdgeButtonAutoHidden:animated:"), YES, animated);
        } else if (!NFBGet(owner, @"trayBackdrop") && CACurrentMediaTime() >= trayDismissUntil) {
            // This is the exact native panel displayed in the reference image.
            // Do not replace the separate up/down swipe-selection gesture.
            SEL active = NSSelectorFromString(@"swipeGestureActive");
            if (!((BOOL (*)(id, SEL))objc_msgSend)(owner, active))
                originalShowTray(owner, NSSelectorFromString(@"showTray"));
        }
    } @finally {
        applyingPresentation = NO;
    }
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
    applyPresentation(owner, YES);
}
static void showEdge(id owner, SEL cmd, BOOL animated) {
    remember(owner);
    if (suppressed()) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(owner, NSSelectorFromString(@"hideEdgeButtonAnimated:"), animated);
        return;
    }
    originalShowEdge(owner, cmd, animated);
    applyPresentation(owner, animated);
}
static void showTray(id owner, SEL cmd) {
    remember(owner);
    if (!suppressed() && (!enabledByOwner || !shouldTuck())) originalShowTray(owner, cmd);
}
static void hideTray(id owner, SEL cmd, BOOL animated) {
    remember(owner);
    if (enabledByOwner && !applyingPresentation)
        trayDismissUntil = CACurrentMediaTime() + (animated ? 0.45 : 0);
    originalHideTray(owner, cmd, animated);
    // Allow native selection/collapse/teardown to finish before applying the
    // current state again. Fullscreen and split suppression will stay closed.
    if (enabledByOwner && !applyingPresentation) NFBOpenEdgeAfterClose();
}
// Native hide completion writes hidden=YES even when its animation was interrupted.
// Reconcile after transitions, retaining the native eligibility/settings decision.
static NSUInteger restoreGeneration;
static void reconcile(void) {
    if (!installed || suppressed()) return;
    for (id owner in owners.allObjects) {
        originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
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
        applyPresentation(owner, NO);
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
// Apply the current suppression state, restoring the native edge icon when the
// split bubbles leave the screen.
static void applySuppression(void) {
    if (!installed) return;
    BOOL now = suppressed();
    BOOL fullscreen = shouldTuck();
    if (now == lastSuppressed && fullscreen == lastFullscreen && enabledByOwner == lastEnabled) {
        // Reopen after native dismissal/animation completion, even when the
        // desktop state itself did not change between manager ticks.
        if (!now) for (id owner in owners.allObjects) applyPresentation(owner, NO);
        return;
    }
    lastSuppressed = now;
    lastFullscreen = fullscreen;
    lastEnabled = enabledByOwner;
    if (now) ++restoreGeneration;
    else NFBOpenEdgeAfterClose();
    for (id owner in owners.allObjects) {
        originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
        applyPresentation(owner, YES);
    }
    // On restoration, native shouldShowEdgeIcon still checks the user's own settings.
    NFBDebugLog(@"Open tray policy: hidden=%d fullscreen=%d owners=%lu", now, fullscreen, (unsigned long)owners.count);
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
            !matches(cls, @"showTray", @encode(void), NULL) ||
            !matches(cls, @"hideTrayAnimated:", @encode(void), @encode(BOOL)) ||
            !matches(cls, @"trayBackdrop", @encode(id), NULL) ||
            !matches(cls, @"swipeGestureActive", @encode(BOOL), NULL)) return;
        Method tuckMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"setEdgeButtonAutoHidden:animated:"));
        if (!tuckMethod) return;
        NSMethodSignature *tuckSig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(tuckMethod)];
        if (strcmp(tuckSig.methodReturnType, @encode(void)) || tuckSig.numberOfArguments != 4 ||
            strcmp([tuckSig getArgumentTypeAtIndex:2], @encode(BOOL)) ||
            strcmp([tuckSig getArgumentTypeAtIndex:3], @encode(BOOL))) return;
        owners = [NSHashTable weakObjectsHashTable];
        MSHookMessageEx(cls, NSSelectorFromString(@"shouldShowEdgeIcon"), (IMP)shouldShow, (IMP *)&originalShouldShow);
        MSHookMessageEx(cls, NSSelectorFromString(@"refreshUI"), (IMP)refresh, (IMP *)&originalRefresh);
        MSHookMessageEx(cls, NSSelectorFromString(@"showEdgeButtonAnimated:"), (IMP)showEdge, (IMP *)&originalShowEdge);
        MSHookMessageEx(cls, NSSelectorFromString(@"showTray"), (IMP)showTray, (IMP *)&originalShowTray);
        MSHookMessageEx(cls, NSSelectorFromString(@"hideTrayAnimated:"), (IMP)hideTray, (IMP *)&originalHideTray);
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
