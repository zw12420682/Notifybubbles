#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "NFBBackProtocol.h"
#include <notify.h>

static UIViewController *NFBVisibleController(UIViewController *controller) {
    for (NSUInteger depth = 0; controller && depth < 30; depth++) {
        UIViewController *next = nil;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            next = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class])
            next = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class])
            next = ((UITabBarController *)controller).selectedViewController;
        if (!next || next == controller) break;
        controller = next;
    }
    return controller;
}
static WKWebView *NFBBackWebView(UIView *view, NSUInteger depth) {
    // Under TrollOpen the app's view may be re-parented into a floating container,
    // so its `window` relationship can be nil or point at an unusual window while
    // still being on screen. Drop the `window` check; rely on visibility only.
    if (depth > 30 || !view || view.hidden || view.alpha < 0.01) return nil;
    if ([view isKindOfClass:WKWebView.class] && ((WKWebView *)view).canGoBack) return (WKWebView *)view;
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        WKWebView *web = NFBBackWebView(child, depth + 1);
        if (web) return web;
    }
    return nil;
}
static BOOL NFBPerformBack(void) {
    // This tweak runs INSIDE the target app's own process, so it must operate on
    // that app's own windows — never another process. TrollOpen floats the app in
    // a window while the app's scene may report Background (the system foreground
    // is a different app or the home screen). A Foreground-only scene filter, and
    // a window-level filter, both incorrectly discard the very window we need.
    // So: accept every visible window of every window scene, then choose the one
    // that actually carries a navigation stack or a web view (the app's content),
    // falling back to the key window.
    NSMutableArray<UIWindow *> *candidates = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.01 || !window.rootViewController) continue;
            [candidates addObject:window];
        }
    }
    if (candidates.count == 0) {
        NSLog(@"[NotifyBubblesBack] no visible window candidates (scene state filter removed)");
        return NO;
    }
    // Prefer the window whose visible controller owns a navigation stack with a
    // real back item, or that hosts a web view that can go back. Only fall back to
    // the key window or the first candidate when none carries a back action.
    UIWindow *window = nil;
    for (UIWindow *candidate in candidates) {
        UIViewController *controller = NFBVisibleController(candidate.rootViewController);
        UINavigationController *nav = controller.navigationController;
        if ((nav && nav.visibleViewController == controller && nav.viewControllers.count > 1) ||
            NFBBackWebView(controller.viewIfLoaded, 0)) {
            window = candidate;
            break;
        }
    }
    if (!window) {
        for (UIWindow *candidate in candidates) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }
    if (!window) window = candidates.firstObject;
    // Try the preferred window first, then fall back to every other candidate.
    // A floating container may re-parent the content view so the "preferred"
    // window's controller relationship is empty while a real nav stack still
    // exists on another window. Walk all candidates and pop the first valid one.
    NSMutableArray<UIWindow *> *ordered = [NSMutableArray arrayWithObject:window];
    for (UIWindow *candidate in candidates) {
        if (candidate != window) [ordered addObject:candidate];
    }
    for (UIWindow *candidate in ordered) {
        UIViewController *visible = NFBVisibleController(candidate.rootViewController);
        if (!visible || visible.transitionCoordinator || [visible isKindOfClass:UIAlertController.class]) continue;
        UINavigationController *nav = visible.navigationController;
        if (nav && nav.visibleViewController == visible && nav.viewControllers.count > 1 && !nav.transitionCoordinator) {
            // A custom left button may mean menu/delete, not back. Do not invoke it.
            if (visible.navigationItem.leftBarButtonItem || visible.navigationItem.leftBarButtonItems.count) continue;
            if (visible.navigationItem.hidesBackButton) continue;
            BOOL popped = [nav popViewControllerAnimated:YES] != nil;
            NSLog(@"[NotifyBubblesBack] nav pop %@ count=%lu", popped ? @"OK" : @"FAIL",
                  (unsigned long)nav.viewControllers.count);
            return popped;
        }
        WKWebView *web = NFBBackWebView(visible.viewIfLoaded, 0);
        if (web) { [web goBack]; NSLog(@"[NotifyBubblesBack] webview goBack OK"); return YES; }
    }
    NSLog(@"[NotifyBubblesBack] no back action found across %lu windows", (unsigned long)ordered.count);
    return NO;
}
__attribute__((constructor)) static void NFBInstallAppBack(void) {
    @autoreleasepool {
        NSString *app = NSBundle.mainBundle.bundleIdentifier;
        if (!app.length || [app isEqual:@"com.apple.springboard"] ||
            ![NSBundle.mainBundle.bundlePath hasSuffix:@".app"] || NSBundle.mainBundle.infoDictionary[@"NSExtension"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *name = NFBBackName(app), *reply = [name stringByAppendingString:@".reply"];
            __block uint64_t lastRequest = 0;
            int token = 0;
            notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int inputToken) {
                uint64_t request = 0;
                if (notify_get_state(inputToken, &request) != NOTIFY_STATUS_OK || request == lastRequest || !NFBBackFresh(request, NFBBackTime())) return;
                lastRequest = request;
                BOOL performed = NO;
                @try { performed = NFBPerformBack(); } @catch (__unused NSException *e) {}
                int responseToken = 0;
                if (notify_register_check(reply.UTF8String, &responseToken) == NOTIFY_STATUS_OK) {
                    notify_set_state(responseToken, (request << 2) | (performed ? 1 : 2));
                    notify_post(reply.UTF8String);
                    notify_cancel(responseToken);
                }
            });
        });
    }
}
