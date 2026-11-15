// Explicitly armed, bounded, read-only SpringBoard hierarchy snapshots.
// Never log labels/text, change windows, call hitTest, or invoke gesture actions.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import "NFBDebugLog.h"

static NSUInteger nfbArcEpoch;
static NSString *NFBArcImage(Class cls) {
    Dl_info info = {0};
    if (dladdr((__bridge const void *)cls, &info) && info.dli_fname)
        return [NSString stringWithUTF8String:info.dli_fname].lastPathComponent;
    return @"unknown";
}
static void NFBArcTree(UIView *view, UIWindow *window, NSUInteger depth,
                       NSUInteger *visited, NSUInteger *emitted) {
    if (*visited >= 1800 || *emitted >= 120 || depth > 28) return;
    ++*visited;
    if (view.hidden || view.alpha < 0.01) return;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGRect area = CGRectMake(window.bounds.size.width * 0.35,
        window.bounds.size.height * 0.55, window.bounds.size.width * 0.65,
        window.bounds.size.height * 0.45);
    NSString *name = NSStringFromClass(view.class);
    BOOL custom = ![name hasPrefix:@"UI"] && ![name hasPrefix:@"_UI"] &&
                  ![name hasPrefix:@"SB"] && ![name hasPrefix:@"BS"];
    if (depth <= 2 || (CGRectIntersectsRect(frame, area) &&
                      (custom || view.gestureRecognizers.count || view.userInteractionEnabled))) {
        ++*emitted;
        NSUInteger index = view.superview ? [view.superview.subviews indexOfObjectIdenticalTo:view] : 0;
        NFBDebugLog(@"arc-diag: view=%p class=%@ image=%@ window=%p parent=%p index=%lu depth=%lu frame=%@ z=%.2f alpha=%.2f interaction=%d clips=%d children=%lu",
            view, name, NFBArcImage(view.class), window, view.superview,
            (unsigned long)index, (unsigned long)depth, NSStringFromCGRect(frame),
            view.layer.zPosition, view.alpha, view.userInteractionEnabled,
            view.clipsToBounds, (unsigned long)view.subviews.count);
        NSUInteger count = 0;
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if (count++ >= 8) break;
            NFBDebugLog(@"arc-diag: gesture=%p class=%@ image=%@ view=%p enabled=%d state=%ld cancels=%d delays=%d/%d delegate=%@",
                gesture, NSStringFromClass(gesture.class), NFBArcImage(gesture.class),
                view, gesture.enabled, (long)gesture.state, gesture.cancelsTouchesInView,
                gesture.delaysTouchesBegan, gesture.delaysTouchesEnded,
                gesture.delegate ? NSStringFromClass([(id)gesture.delegate class]) : @"nil");
        }
    }
    // Do not prune on parent frame: overlays can extend beyond unclipped parents.
    for (UIView *child in view.subviews) {
        NFBArcTree(child, window, depth + 1, visited, emitted);
        if (*visited >= 1800 || *emitted >= 120) break;
    }
}
static void NFBArcSnapshot(NSUInteger epoch, NSUInteger sample) {
    if (epoch != nfbArcEpoch || !NFBDebugLoggingEnabled()) return;
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    id lock = NFBGet((id)lockClass, @"sharedInstance");
    if (NFBCheckedBool(lock, @"isUILocked", YES)) {
        ++nfbArcEpoch;
        NFBDebugLog(@"arc-diag: cancelled on lock");
        return;
    }
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    NFBDebugLog(@"arc-diag: BEGIN epoch=%lu sample=%lu windows=%lu scope=SpringBoard-only",
        (unsigned long)epoch, (unsigned long)sample, (unsigned long)windows.count);
    NSUInteger visited = 0, emitted = 0, count = 0;
    for (UIWindow *window in windows) {
        if (count++ >= 48) break;
        NFBDebugLog(@"arc-diag: window=%p class=%@ image=%@ level=%.2f hidden=%d alpha=%.2f interaction=%d key=%d frame=%@ root=%@ scene=%@",
            window, NSStringFromClass(window.class), NFBArcImage(window.class),
            window.windowLevel, window.hidden, window.alpha, window.userInteractionEnabled,
            window.isKeyWindow, NSStringFromCGRect(window.frame),
            window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"nil",
            window.windowScene.session.persistentIdentifier);
    }
    // Visit top-level windows in reverse enumeration order to reduce starvation.
    count = 0;
    for (UIWindow *window in windows.reverseObjectEnumerator) {
        if (count++ >= 48) break;
        if (!window.hidden && window.alpha >= 0.01) {
            NSUInteger localVisited = 0, localEmitted = 0;
            NFBArcTree(window, window, 0, &localVisited, &localEmitted);
            visited += localVisited; emitted += localEmitted;
        }
    }
    NFBDebugLog(@"arc-diag: END epoch=%lu sample=%lu visited=%lu emitted=%lu caps=1800nodes/120rows-per-window,48windows,depth28",
        (unsigned long)epoch, (unsigned long)sample, (unsigned long)visited, (unsigned long)emitted);
}
static void NFBArmArcDiagnostics(void) {
    if (!NFBDebugLoggingEnabled()) return;
    NSUInteger epoch = ++nfbArcEpoch;
    NFBDebugLog(@"arc-diag: armed epoch=%lu snapshots at 0/6/12/18/24 seconds; rearm replaces old capture",
        (unsigned long)epoch);
    for (NSUInteger sample = 0; sample < 5; ++sample) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sample * 6 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                @try { NFBArcSnapshot(epoch, sample); }
                @catch (NSException *error) { NFBErrorLog(@"arc-diag: snapshot failed %@", error.name); }
            });
    }
}
