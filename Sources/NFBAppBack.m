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
    if (depth > 30 || view.hidden || view.alpha < 0.01 || !view.window) return nil;
    if ([view isKindOfClass:WKWebView.class] && ((WKWebView *)view).canGoBack) return (WKWebView *)view;
    for (UIView *child in view.subviews.reverseObjectEnumerator) {
        WKWebView *web = NFBBackWebView(child, depth + 1);
        if (web) return web;
    }
    return nil;
}
static BOOL NFBPerformBack(void) {
    NSMutableArray<UIWindow *> *candidates = [NSMutableArray array];
    UIWindow *key = nil;
    // TrollOpen floats the app in a window whose level is above UIWindowLevelNormal,
    // so a strict level check here would discard the very window we need. Accept
    // every visible window carrying a root view controller, then prefer the key
    // window or the lowest-level one (the app's own content, not system overlays).
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            (scene.activationState != UISceneActivationStateForegroundActive &&
             scene.activationState != UISceneActivationStateForegroundInactive)) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.01 || !window.rootViewController) continue;
            // Skip the obvious system overlays (keyboard, status bar, text effects).
            if (window.windowLevel > UIWindowLevelAlert) continue;
            [candidates addObject:window];
            if (window.isKeyWindow) key = window;
        }
    }
    UIWindow *window = nil;
    if (key && [candidates containsObject:key]) window = key;
    else if (candidates.count == 1) window = candidates.firstObject;
    else {
        // Pick the lowest window level: the app's real content sits below
        // TrollOpen's own floating chrome.
        [candidates sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
            if (a.windowLevel < b.windowLevel) return NSOrderedAscending;
            if (a.windowLevel > b.windowLevel) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        window = candidates.firstObject;
    }
    if (!window) return NO;
    UIViewController *visible = NFBVisibleController(window.rootViewController);
    if (!visible || visible.transitionCoordinator || [visible isKindOfClass:UIAlertController.class]) return NO;
    UINavigationController *nav = visible.navigationController;
    if (nav && nav.visibleViewController == visible && nav.viewControllers.count > 1 && !nav.transitionCoordinator) {
        // A custom left button may mean menu/delete, not back. Do not invoke it.
        if (visible.navigationItem.leftBarButtonItem || visible.navigationItem.leftBarButtonItems.count) return NO;
        if (visible.navigationItem.hidesBackButton) return NO;
        return [nav popViewControllerAnimated:YES] != nil;
    }
    WKWebView *web = NFBBackWebView(visible.viewIfLoaded, 0);
    if (web) { [web goBack]; return YES; }
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
