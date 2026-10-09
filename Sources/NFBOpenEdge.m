#import "NFBWindowState.h"
#import "NFBTransitionPolicy.h"
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
static NSUInteger sceneEpoch = 1;
static NSString *lastSceneKey;
static NSMapTable *appliedEpochs;
static void (*originalHideTray)(id, SEL, BOOL);
static NSHashTable *owners;
static BOOL (*originalShouldShow)(id, SEL);
static void (*originalRefresh)(id, SEL);
static void (*originalShowEdge)(id, SEL, BOOL);
static void (*originalShowTray)(id, SEL);
static BOOL shouldTuck(void) { return NFBCurrentWindowState().fullscreen; }
static BOOL suppressed(void) {
    // Hide Open's edge icon only while NotifyBubbles' split bubbles are on screen.
    // Expansion means the native tray (delete/collapse/app icons), not the
    // horizontal position of a single edge button.
    return enabledByOwner && splitIconsVisible && NSThread.isMainThread;
}
static NSString *candidateSceneKey;
static NSUInteger candidateRevision;
static CFTimeInterval candidateSince;
static NSMapTable *manualSceneKeys;
static NSString *sceneKey(void) { return NFBCurrentWindowState().sceneKey; }
static void applySuppression(void);
// All panel content and gestures remain owned by Open. Reentrancy is possible:
// showing/hiding its tray can call the intercepted edge/refresh methods.
static void applyPresentation(id owner, BOOL animated) {
    if (applyingPresentation || !enabledByOwner || !NSThread.isMainThread) return;
    // A scene transition supplies one default action. Refreshes and delayed
    // reconciliation must not undo subsequent manual collapse/expansion.
    if (!suppressed() && candidateSceneKey) return;
    if (!NFBTransitionNeedsAction(sceneEpoch, [[appliedEpochs objectForKey:owner] unsignedIntegerValue])) return;
    applyingPresentation = YES;
    @try {
        if (suppressed()) {
            [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
            if (NFBGet(owner, @"trayBackdrop"))
                originalHideTray(owner, NSSelectorFromString(@"hideTrayAnimated:"), NO);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(owner,
                NSSelectorFromString(@"hideEdgeButtonAnimated:"), animated);
            return;
        }
        if (!originalShouldShow(owner, NSSelectorFromString(@"shouldShowEdgeIcon"))) return;
        if (lastFullscreen) {
            [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
            if (NFBGet(owner, @"trayBackdrop"))
                originalHideTray(owner, NSSelectorFromString(@"hideTrayAnimated:"), NO);
            ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(owner,
                NSSelectorFromString(@"setEdgeButtonAutoHidden:animated:"), YES, animated);
        } else if (!NFBGet(owner, @"trayBackdrop") && CACurrentMediaTime() >= trayDismissUntil) {
            // This is the exact native panel displayed in the reference image.
            // Do not replace the separate up/down swipe-selection gesture.
            SEL active = NSSelectorFromString(@"swipeGestureActive");
            if (!((BOOL (*)(id, SEL))objc_msgSend)(owner, active)) {
                originalShowTray(owner, NSSelectorFromString(@"showTray"));
                if (NFBGet(owner, @"trayBackdrop"))
                    [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
            }
        } else if (NFBGet(owner, @"trayBackdrop")) {
            [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
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
    BOOL wasApplying = applyingPresentation;
    applyingPresentation = YES;
    @try { originalRefresh(owner, cmd); } @finally { applyingPresentation = wasApplying; }
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
    if (!suppressed()) {
        originalShowTray(owner, cmd);
        if (enabledByOwner && !applyingPresentation && NFBGet(owner, @"trayBackdrop")) {
            [manualSceneKeys setObject:sceneKey() forKey:owner];
            [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
        }
    }
}
static void hideTray(id owner, SEL cmd, BOOL animated) {
    remember(owner);
    if (enabledByOwner && !applyingPresentation) {
        trayDismissUntil = CACurrentMediaTime() + (animated ? 0.45 : 0);
        [manualSceneKeys setObject:sceneKey() forKey:owner];
        [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
    }
    originalHideTray(owner, cmd, animated);
    // Native collapse is final for this scene; do not schedule automatic reopen.
}
// Native hide completion writes hidden=YES even when its animation was interrupted.
// Reconcile after transitions, retaining the native eligibility/settings decision.
static NSUInteger restoreGeneration;
static void reconcile(void) {
    if (!installed || suppressed()) return;
    for (id owner in owners.allObjects) {
        refresh(owner, NSSelectorFromString(@"refreshUI"));
        BOOL allowed = originalShouldShow(owner, NSSelectorFromString(@"shouldShowEdgeIcon"));
        SEL getter = NSSelectorFromString(@"edgeButton");
        NSMethodSignature *sig = NFBSignature(owner, getter);
        if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') continue;
        UIView *button = ((id (*)(id, SEL))objc_msgSend)(owner, getter);
        if (![button isKindOfClass:UIView.class]) continue;
        // Do not expose the button behind an intentionally open tray.
        SEL trayGetter = NSSelectorFromString(@"trayBackdrop");
        NSMethodSignature *traySig = NFBSignature(owner, trayGetter);
        if (!traySig || traySig.numberOfArguments != 2 || traySig.methodReturnType[0] != '@') continue;
        id tray = ((id (*)(id, SEL))objc_msgSend)(owner, trayGetter);
        if (allowed && !tray && (button.hidden || button.alpha < 0.01))
            originalShowEdge(owner, NSSelectorFromString(@"showEdgeButtonAnimated:"), NO);
        applyPresentation(owner, NO);
        NFBDebugLog(@"Open edge restore: eligible=%d hidden=%d alpha=%.2f owners=%lu",
            allowed, button.hidden, button.alpha, (unsigned long)owners.count);
    }
}
static void scheduleRestore(NSUInteger generation, NSUInteger attempt) {
    static const double delays[] = {0.15, 0.30, 0.45, 0.60, 0.70};
    if (attempt >= 5) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[attempt] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != restoreGeneration || !enabledByOwner || suppressed()) return;
        NFBInvalidateWindowState();
        reconcile();
        BOOL allApplied = !candidateSceneKey;
        for (id owner in owners.allObjects) {
            if (NFBTransitionNeedsAction(sceneEpoch, [[appliedEpochs objectForKey:owner] unsignedIntegerValue])) allApplied = NO;
            UIView *button = NFBGet(owner, @"edgeButton");
            if ([button isKindOfClass:UIView.class] && button.hidden && !NFBGet(owner, @"trayBackdrop") && originalShouldShow(owner, NSSelectorFromString(@"shouldShowEdgeIcon"))) allApplied = NO;
        }
        if (NFBShouldRetryRestore(enabledByOwner, suppressed(), owners.count > 0, allApplied)) scheduleRestore(generation, attempt + 1);
    });
}
void NFBOpenEdgeAfterClose(void) {
    if (!NSThread.isMainThread || !enabledByOwner) return;
    scheduleRestore(++restoreGeneration, 0);
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
    NSString *key = sceneKey();
    BOOL immediate = !lastSceneKey || now != lastSuppressed || enabledByOwner != lastEnabled;
    if (!immediate && (![lastSceneKey isEqual:key] || fullscreen != lastFullscreen)) {
        if (![candidateSceneKey isEqual:key]) {
            candidateSceneKey = [key copy];
            candidateSince = CACurrentMediaTime();
            NSUInteger revision = ++candidateRevision;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.13 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (revision != candidateRevision) return;
                NFBInvalidateWindowState();
                applySuppression();
            });
            return;
        }
        if (!NFBTransitionStable(CACurrentMediaTime(), candidateSince)) return;
    }
    candidateSceneKey = nil;
    ++candidateRevision;
    if (now == lastSuppressed && fullscreen == lastFullscreen && enabledByOwner == lastEnabled &&
        [lastSceneKey isEqualToString:key]) {
        // Only incomplete transition work may retry. Completed actions are
        // consumed per owner, so manual control remains untouched.
        if (!now) for (id owner in owners.allObjects) applyPresentation(owner, NO);
        return;
    }
    ++sceneEpoch;
    for (id owner in owners.allObjects) {
        if (!now && [[manualSceneKeys objectForKey:owner] isEqual:key]) [appliedEpochs setObject:@(sceneEpoch) forKey:owner];
        [manualSceneKeys removeObjectForKey:owner];
    }
    lastSceneKey = [key copy];
    lastSuppressed = now;
    lastFullscreen = fullscreen;
    lastEnabled = enabledByOwner;
    if (now) ++restoreGeneration;
    else NFBOpenEdgeAfterClose();
    for (id owner in owners.allObjects) {
        refresh(owner, NSSelectorFromString(@"refreshUI"));
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
        appliedEpochs = [NSMapTable weakToStrongObjectsMapTable];
        manualSceneKeys = [NSMapTable weakToStrongObjectsMapTable];
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
