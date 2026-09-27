#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "NFBBackProtocol.h"
#import "NFBDebugLog.h"
#include <notify.h>

static BOOL NFBBackVisible(UIView *view) {
    if (!view || !view.window || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *v = view; v; v = v.superview) if (v.hidden || v.alpha < 0.01) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window], view.window.bounds);
}
static WKWebView *NFBBackWebView(UIView *view, NSUInteger depth) {
    if (depth > 30 || !NFBBackVisible(view)) return nil;
    if ([view isKindOfClass:WKWebView.class]) return ((WKWebView *)view).canGoBack ? (WKWebView *)view : nil;
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        WKWebView *found = NFBBackWebView(child, depth + 1);
        if (found) return found;
    }
    return nil;
}
static uint8_t NFBPerformBack(void) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    UIWindow *target = nil;
    for (UIWindow *window in windows) {
        if (!NFBBackVisible(window) || !window.rootViewController) continue;
        if (window.isKeyWindow) { target = window; break; }
        if (!target && window.windowLevel == UIWindowLevelNormal) target = window;
    }
    if (!target) return NFBBackStatusNoWindow;
    UIViewController *visible = target.rootViewController;
    // Follow only the currently displayed branch; never pop an inactive tab.
    for (NSUInteger depth = 0; visible && depth < 30; depth++) {
        if (visible.transitionCoordinator || visible.isBeingDismissed || [visible isKindOfClass:UIAlertController.class]) return NFBBackStatusTransitioning;
        UIViewController *next = visible.presentedViewController;
        if (!next && [visible isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)visible).visibleViewController;
        if (!next && [visible isKindOfClass:UITabBarController.class]) next = ((UITabBarController *)visible).selectedViewController;
        if (!next) {
            NSMutableArray *shown = [NSMutableArray array];
            for (UIViewController *child in visible.childViewControllers)
                if (child.isViewLoaded && NFBBackVisible(child.viewIfLoaded)) [shown addObject:child];
            if (shown.count == 1) next = shown.firstObject;
        }
        if (!next || next == visible) break;
        visible = next;
    }
    if (!visible || !NFBBackVisible(visible.viewIfLoaded)) return NFBBackStatusNoBackAction;
    if (visible.transitionCoordinator || [visible isKindOfClass:UIAlertController.class]) return NFBBackStatusTransitioning;
    WKWebView *web = NFBBackWebView(visible.viewIfLoaded, 0);
    if (web) { [web goBack]; return NFBBackStatusPerformed; }
    for (UIViewController *page = visible; page; page = page.parentViewController) {
        UINavigationController *nav = page.navigationController;
        if (nav && nav.visibleViewController == page && nav.viewControllers.count > 1 && !nav.transitionCoordinator) {
            return [nav popViewControllerAnimated:YES] ? NFBBackStatusPerformed : NFBBackStatusNoBackAction;
        }
    }
    // No dismiss, home gesture, synthesized touch, or background-stack fallback.
    return NFBBackStatusNoBackAction;
}
__attribute__((constructor)) static void NFBInstallAppBack(void) {
    @autoreleasepool {
        NSString *app = NSBundle.mainBundle.bundleIdentifier;
        NSString *path = NSBundle.mainBundle.bundlePath;
        BOOL isSpringBoard = [app isEqual:@"com.apple.springboard"];
        BOOL isApp = path.length && [path hasSuffix:@".app"];
        BOOL isExtension = NSBundle.mainBundle.infoDictionary[@"NSExtension"] != nil;
        // Log on every process we land in so the debug file reveals where the
        // back tweak actually injected (or did not inject).
        NFBDebugLog(@"back constructor app=%@ springboard=%d isApp=%d extension=%d logpaths=%@",
                    app ?: @"<nil>", isSpringBoard, isApp, isExtension, NFBDebugLogPaths());
        if (!app.length || isSpringBoard || !isApp || isExtension) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *name = NFBBackName(app), *reply = [name stringByAppendingString:@".reply"];
            __block uint64_t lastRequest = 0;
            int token = 0;
            uint32_t reg = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int inputToken) {
                uint64_t request = 0;
                if (notify_get_state(inputToken, &request) != NOTIFY_STATUS_OK || request == lastRequest || !NFBBackFresh(request, NFBBackTime())) {
                    NFBDebugLog(@"back request ignored state=%llu last=%llu now=%llu",
                                request, lastRequest, NFBBackTime());
                    return;
                }
                lastRequest = request;
                NFBDebugLog(@"=== back request %llu for %@ ===", request, app);
                uint8_t status = NFBBackStatusException;
                @try { status = NFBPerformBack(); } @catch (__unused NSException *e) {
                    NFBDebugLog(@"perform back threw: %@", e);
                }
                NFBDebugLog(@"=== back result status=%u ===", (unsigned)status);
                int responseToken = 0;
                if (notify_register_check(reply.UTF8String, &responseToken) == NOTIFY_STATUS_OK) {
                    notify_set_state(responseToken, (request << NFBBackStatusShift) | (status & 0xF));
                    notify_post(reply.UTF8String);
                    notify_cancel(responseToken);
                } else {
                    NFBDebugLog(@"reply register failed");
                }
            });
            NFBDebugLog(@"back listener registered name=%@ token=%d status=%u", name, token, reg);
        });
    }
}
