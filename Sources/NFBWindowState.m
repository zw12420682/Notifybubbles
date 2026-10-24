#import "NFBWindowState.h"
#import "NFBPrivate.h"
@implementation NFBWindowState
@end
static NFBWindowState *snapshot;
static NSUInteger generation;
void NFBInvalidateWindowState(void) {
    if (!NSThread.isMainThread) return;
    snapshot = nil; ++generation;
}
NFBWindowState *NFBCurrentWindowState(void) {
    if (!NSThread.isMainThread) return nil;
    if (snapshot) return snapshot;
    NFBWindowState *state = [NFBWindowState new];
    id app = UIApplication.sharedApplication;
    state.home = NFBCheckedBool(app, @"isShowingHomescreen", NO);
    state.frontApp = state.home ? nil : NFBString(NFBGet(NFBGet(app,
        @"_accessibilityFrontMostApplication"), @"bundleIdentifier"));
    id floating = NFBGet(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
    if ([floating isKindOfClass:UIView.class] && ![(UIView *)floating isHidden] && [(UIView *)floating alpha] > 0.01) {
        state.floatingWindow = floating;
    } else {
        Class cls = NSClassFromString(@"FloatingAppWindow");
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (cls && [window isKindOfClass:cls] && !window.hidden && window.alpha > 0.01) {
                    state.floatingWindow = window; break;
                }
            if (state.floatingWindow) break;
        }
    }
    state.floatingApp = NFBString(NFBGet(state.floatingWindow, @"bundleID"));
    SEL mini = NSSelectorFromString(@"miniWindowModeEnabled");
    NSMethodSignature *sig = NFBSignature(state.floatingWindow, mini);
    if (sig.numberOfArguments == 2 && (sig.methodReturnType[0] == 'B' || sig.methodReturnType[0] == 'c'))
        @try { state.mini = ((BOOL (*)(id, SEL))objc_msgSend)(state.floatingWindow, mini); }
        @catch (__unused NSException *error) { state.mini = NO; }
    state.fullscreen = !state.home && !state.floatingWindow && state.frontApp.length > 0;
    state.sceneKey = [NSString stringWithFormat:@"%@|%@|%d|%d",
        state.home ? @"home" : (state.frontApp ?: @"none"), state.floatingApp ?: @"none",
        state.floatingWindow != nil, state.mini];
    snapshot = state;
    NSUInteger token = ++generation;
    dispatch_async(dispatch_get_main_queue(), ^{ if (generation == token) snapshot = nil; });
    return state;
}
