#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "NFBBackProtocol.h"
#import "NFBDebugLog.h"
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
// Collect every UINavigationController reachable anywhere below (or presented
// from) the given controller. TrollOpen's hosted scene can break the
// `visible.navigationController` parent link while the navigation stack itself
// still exists in the tree, so a deep search is the reliable way to find it.
static void NFBCollectNavigationControllers(UIViewController *controller,
    NSMutableArray<UINavigationController *> *out, NSUInteger depth) {
    if (!controller || depth > 30) return;
    if ([controller isKindOfClass:UINavigationController.class])
        [out addObject:(UINavigationController *)controller];
    for (UIViewController *child in controller.childViewControllers)
        NFBCollectNavigationControllers(child, out, depth + 1);
    if (controller.presentedViewController)
        NFBCollectNavigationControllers(controller.presentedViewController, out, depth + 1);
}
// Compact controller-tree dump so the log shows where a navigation stack lives.
static void NFBDumpControllerTree(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 4) return;
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger index = 0; index < depth; index++) [indent appendString:@"  "];
    NFBDebugLog(@"%@tree %@ children=%lu presented=%@",
                indent, NSStringFromClass(controller.class),
                (unsigned long)controller.childViewControllers.count,
                controller.presentedViewController ? NSStringFromClass(controller.presentedViewController.class) : @"<nil>");
    for (UIViewController *child in controller.childViewControllers)
        NFBDumpControllerTree(child, depth + 1);
    if (controller.presentedViewController)
        NFBDumpControllerTree(controller.presentedViewController, depth + 1);
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
    NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;
    NFBDebugLog(@"--- perform back: %lu scenes ---", (unsigned long)scenes.count);
    for (UIScene *scene in scenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        NFBDebugLog(@"scene %@ state=%ld windows=%lu session=%@",
                    NSStringFromClass(scene.class), (long)scene.activationState,
                    (unsigned long)((UIWindowScene *)scene).windows.count,
                    scene.session ? NSStringFromClass(scene.session.class) : @"<nil>");
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NFBDebugLog(@"  scene window %p hidden=%d alpha=%.2f level=%.1f key=%d root=%@",
                        (__bridge void *)window, window.hidden, window.alpha, window.windowLevel, window.isKeyWindow,
                        window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"<nil>");
            if (window.hidden || window.alpha < 0.01 || !window.rootViewController) continue;
            [candidates addObject:window];
        }
    }
    // TrollOpen may host the app's content window OUTSIDE its own scene. The
    // global UIApplication.windows list can still see it. Merge any window not
    // already collected (dedupe by pointer). The property is deprecated since
    // iOS 15 and theos builds with -Werror, but it remains fully functional on
    // iOS 16; silence the warning for this deliberate legacy-API use.
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIWindow *> *globalWindows = UIApplication.sharedApplication.windows;
    #pragma clang diagnostic pop
    NFBDebugLog(@"global UIApplication.windows=%lu", (unsigned long)globalWindows.count);
    for (UIWindow *window in globalWindows) {
        NFBDebugLog(@"  global window %p hidden=%d alpha=%.2f level=%.1f key=%d root=%@",
                    (__bridge void *)window, window.hidden, window.alpha, window.windowLevel, window.isKeyWindow,
                    window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"<nil>");
        if (window.hidden || window.alpha < 0.01 || !window.rootViewController) continue;
        if ([candidates containsObject:window]) continue;
        [candidates addObject:window];
        NFBDebugLog(@"  (extra, not in any scene)");
    }
    if (candidates.count == 0) {
        NFBDebugLog(@"no visible window candidates; nothing to operate on");
        return NO;
    }
    NFBDebugLog(@"window candidates total=%lu", (unsigned long)candidates.count);
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
    NFBDebugLog(@"preferred window=%p root=%@", (__bridge void *)window,
                window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"<nil>");
    NFBDumpControllerTree(window.rootViewController, 0);
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
        if (!visible || visible.transitionCoordinator || [visible isKindOfClass:UIAlertController.class]) {
            NFBDebugLog(@"skip window %p: visible=%@ transition=%d alert=%d", (__bridge void *)candidate,
                        visible ? NSStringFromClass(visible.class) : @"<nil>",
                        visible && visible.transitionCoordinator != nil,
                        [visible isKindOfClass:UIAlertController.class]);
            continue;
        }
        UINavigationController *nav = visible.navigationController;
        if (nav && nav.visibleViewController == visible && nav.viewControllers.count > 1 && !nav.transitionCoordinator) {
            // A custom left button may mean menu/delete, not back. Do not invoke it.
            if (visible.navigationItem.leftBarButtonItem || visible.navigationItem.leftBarButtonItems.count) {
                NFBDebugLog(@"nav has custom left button, skip");
                continue;
            }
            if (visible.navigationItem.hidesBackButton) {
                NFBDebugLog(@"nav hidesBackButton, skip");
                continue;
            }
            BOOL popped = [nav popViewControllerAnimated:YES] != nil;
            NFBDebugLog(@"nav pop (direct) %@ stack=%lu", popped ? @"OK" : @"FAIL",
                        (unsigned long)nav.viewControllers.count);
            if (popped) return YES;
        }
        // Deep search: the parent link can be broken under TrollOpen hosting even
        // though a navigation stack with back history still exists in the tree.
        NSMutableArray<UINavigationController *> *navs = [NSMutableArray array];
        NFBCollectNavigationControllers(candidate.rootViewController, navs, 0);
        NFBDebugLog(@"deep nav search on window %p: found=%lu", (__bridge void *)candidate, (unsigned long)navs.count);
        for (UINavigationController *found in navs) {
            NFBDebugLog(@"  nav %@ stack=%lu visible=%@ transitioning=%d",
                        NSStringFromClass(found.class), (unsigned long)found.viewControllers.count,
                        found.visibleViewController ? NSStringFromClass(found.visibleViewController.class) : @"<nil>",
                        found.transitionCoordinator != nil);
            if (found.viewControllers.count > 1 && !found.transitionCoordinator) {
                BOOL popped = [found popViewControllerAnimated:YES] != nil;
                NFBDebugLog(@"nav pop (deep) %@", popped ? @"OK" : @"FAIL");
                if (popped) return YES;
            }
        }
        WKWebView *web = NFBBackWebView(visible.viewIfLoaded, 0);
        if (web) { [web goBack]; NFBDebugLog(@"webview goBack OK"); return YES; }
    }
    NFBDebugLog(@"no back action found across %lu windows", (unsigned long)ordered.count);
    return NO;
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
                BOOL performed = NO;
                @try { performed = NFBPerformBack(); } @catch (__unused NSException *e) {
                    NFBDebugLog(@"perform back threw: %@", e);
                }
                NFBDebugLog(@"=== back result=%d ===", performed);
                int responseToken = 0;
                if (notify_register_check(reply.UTF8String, &responseToken) == NOTIFY_STATUS_OK) {
                    notify_set_state(responseToken, (request << 2) | (performed ? 1 : 2));
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
