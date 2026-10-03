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
static BOOL installed;
static BOOL lastSuppressed;
static NSHashTable *owners;
static BOOL (*originalShouldShow)(id, SEL);
static void (*originalRefresh)(id, SEL);
static void (*originalShowEdge)(id, SEL, BOOL);
static void (*originalShowTray)(id, SEL);
static BOOL suppressed(void) {
    return enabledByOwner && NSThread.isMainThread && NFBSplitAttachmentApp().length > 0;
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
    for (id owner in owners.allObjects) originalRefresh(owner, NSSelectorFromString(@"refreshUI"));
    // On restoration, native shouldShowEdgeIcon still checks the user's own settings.
    NFBDebugLog(@"Open edge portrait suppression=%d", now);
}
