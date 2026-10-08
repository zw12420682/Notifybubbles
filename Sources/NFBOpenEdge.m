#import "NFBOpenEdge.h"
#import "NFBWindowControls.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <string.h>

// Verified against the supplied Open 1.3.7 binary. Never alter its preferences,
// minimized-app list, notification records or private gesture action pointers.
static BOOL enabledByOwner;
static BOOL splitIconsShown = YES;
static BOOL installed;
static BOOL lastSuppressed;
static NSHashTable *owners;
static BOOL (*originalShouldShow)(id, SEL);
static void (*originalRefresh)(id, SEL);
static void (*originalShowEdge)(id, SEL, BOOL);
static void (*originalShowTray)(id, SEL);
static BOOL suppressed(void) {
    // Suppress the edge icon only while NotifyBubbles shows its own split icons.
    return enabledByOwner && splitIconsShown && NSThread.isMainThread && NFBSplitAttachmentApp().length > 0;
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
    originalRefresh(owner, cmd); // Native false branch animates edge/tray/swipe dismissal.
}
static void showEdge(id owner, SEL cmd, BOOL animated) {
    remember(owner);
    if (suppressed()) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(owner, NSSelectorFromString(@"hideEdgeButtonAnimated:"), animated);
        return;
    }
    originalShowEdge(owner, cmd, animated);
}
static void showTray(id owner, SEL cmd) {
    remember(owner);
    if (!suppressed()) originalShowTray(owner, cmd);
}
// Native hide completion writes hidden=YES even when its animation was interrupted.
// Reconcile after transitions, retaining the native eligibility/settings decision.
static NSUInteger restoreGeneration;
static BOOL expandOnRestore;
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
        if (allowed && !suppressed() && expandOnRestore) {
            // Right-edge inward/left pan resolves mode 1 and calls showTray (1.3.7).
            // Consume only once the tray exists; later retries must not reopen a
            // tray the user subsequently dismissed.
            if (!tray) originalShowTray(owner, NSSelectorFromString(@"showTray"));
            id opened = ((id (*)(id, SEL))objc_msgSend)(owner, trayGetter);
            if (opened) {
                expandOnRestore = NO;
                NFBDebugLog(@"Open rotation: opened inward-swipe app tray");
            }
        }
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
void NFBOpenEdgeExpandAfterRotation(void) {
    NFBOpenEdgeExpand();
}
// Expand the edge icon into its app list (the left-swipe/inward-pan action).
void NFBOpenEdgeExpand(void) {
    if (!NSThread.isMainThread || suppressed()) return;
    expandOnRestore = YES; NFBOpenEdgeAfterClose();
}
static BOOL matches(Class cls, NSString *name, const char *result, const char *argument) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method) return NO;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(sig.methodReturnType, result) || sig.numberOfArguments != (argument ? 3u : 2u)) return NO;
    return !argument || !strcmp([sig getArgumentTypeAtIndex:2], argument);
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
        owners = [NSHashTable weakObjectsHashTable];
        MSHookMessageEx(cls, NSSelectorFromString(@"shouldShowEdgeIcon"), (IMP)shouldShow, (IMP *)&originalShouldShow);
        MSHookMessageEx(cls, NSSelectorFromString(@"refreshUI"), (IMP)refresh, (IMP *)&originalRefresh);
        MSHookMessageEx(cls, NSSelectorFromString(@"showEdgeButtonAnimated:"), (IMP)showEdge, (IMP *)&originalShowEdge);
        MSHookMessageEx(cls, NSSelectorFromString(@"showTray"), (IMP)showTray, (IMP *)&originalShowTray);
        installed = YES;
        NFBDebugLog(@"Open 1.3.7 edge integration installed");
    }
    BOOL now = suppressed();
    if (now == lastSuppressed) return;
    lastSuppressed = now;
    if (now) { ++restoreGeneration; expandOnRestore = NO; }
    else NFBOpenEdgeAfterClose();
    for (id owner in owners.allObjects) originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
    // On restoration, native shouldShowEdgeIcon still checks the user's own settings.
    NFBDebugLog(@"Open edge portrait suppression=%d", now);
}
// Split-icon toggle changed: recompute whether Open's edge icon stays suppressed.
void NFBUpdateOpenEdgeSplitIcons(BOOL show) {
    if (!NSThread.isMainThread) return;
    splitIconsShown = show;
    if (!installed) return;
    BOOL now = suppressed();
    if (now == lastSuppressed) return;
    lastSuppressed = now;
    if (now) { ++restoreGeneration; expandOnRestore = NO; }
    else NFBOpenEdgeAfterClose();
    for (id owner in owners.allObjects) originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
    NFBDebugLog(@"Open edge split-icons suppression=%d", now);
}
