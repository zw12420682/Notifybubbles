#import "NFBDesktopHost.h"
#import "NFBDesktopGeometry.h"
#import "NFBInterfaces.h"
#import "NFBWindowState.h"
#import "NFBSystemDesktop.h"
#import "NFBDebugLog.h"
#import "NFBPrivacy.h"
#import "NFBTrollOpen.h"
#import <QuartzCore/QuartzCore.h>
#ifndef NFB_DESKTOP_SIM_TEST
#import <substrate.h>
#endif
#include <math.h>

@interface NFBDesktopSession : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIView *canvas;
@property(nonatomic, strong) UIView *desktop;
@property(nonatomic, strong) UIView *originalParent;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic) NSUInteger originalIndex;
@property(nonatomic) CGRect originalBounds;
@property(nonatomic) CGPoint originalCenter;
@property(nonatomic) CGAffineTransform originalTransform;
@property(nonatomic) UIViewAutoresizing originalAutoresizing;
@property(nonatomic) BOOL originalTranslates, originalHidden, originalInteraction;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) UIVisualEffectView *backgroundFrost;
@property(nonatomic, strong) UIView *paneBackdrop;
@property(nonatomic, strong) NSMutableArray<UIView *> *appearanceViews;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *appearanceHidden;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *appearanceAlpha;
@property(nonatomic) NSUInteger wallpaperCount;
@property(nonatomic,strong) NSMutableArray<UIView *> *interactionViews;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *interactionValues;
@property(nonatomic,strong) NSMutableArray<UIScrollView *> *scrollViews;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *scrollValues;
@property(nonatomic,strong) NSMutableArray<UIGestureRecognizer *> *touchGestures;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *gestureValues;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic) CGFloat originalWindowLevel, originalWindowAlpha;
@property(nonatomic) BOOL originalWindowHidden, originalWindowInteraction, windowMutated;
@property(nonatomic,strong) UIColor *originalWindowColor;
@property(nonatomic) BOOL originalWindowOpaque;
@property(nonatomic,strong) NSMutableArray<UIView *> *windowSiblings;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *windowSiblingHidden;
@property(nonatomic) NSUInteger blockedHitReports;
@property(nonatomic,strong) UIViewController *desktopController;
@property(nonatomic) BOOL suppliedAppearance;
@property(nonatomic,copy) NSString *pendingApp;
@property(nonatomic) CFTimeInterval pendingDeadline;
@property(nonatomic,strong) UIScrollView *refreshScroll;
@property(nonatomic) CGPoint refreshOffset;
@property(nonatomic,strong) UIView *refreshCover;
- (void)refreshWidgetPage;
- (void)activateDesktop;
- (void)adoptDesktopInteraction;
- (void)restoreDesktopInteraction;
@property(nonatomic, copy) NSString *backgroundApp;
@property(nonatomic) BOOL startedHome;
@property(nonatomic) CGPoint dragStart;
@property(nonatomic) CGRect panelFrame;
@property(nonatomic) BOOL placed;
- (void)drag:(UIPanGestureRecognizer *)gesture;
@property(nonatomic) BOOL restoring, mutated;
- (BOOL)place;
- (void)closePressed;
- (void)check;
- (void)restore;
- (void)adoptDesktopAppearance;
- (void)installPaneBackdrop;
- (void)restoreDesktopAppearance;
@end
static NFBDesktopSession *session;
static UIViewController *NFBDesktopOwner(UIViewController *controller, UIView *view) {
    if (controller.isViewLoaded && controller.view==view) return controller;
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *found=NFBDesktopOwner(child,view);
        if (found) return found;
    }
    return nil;
}
static UIScrollView *NFBDesktopPager(UIView *view) {
    if (view.hidden || view.alpha<0.01) return nil;
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll=(UIScrollView *)view;
        NSString *name=NSStringFromClass(scroll.class);
        if ((scroll.pagingEnabled || [name containsString:@"IconScroll"]) &&
            scroll.bounds.size.width>0 && scroll.contentSize.width>=scroll.bounds.size.width*2)
            return scroll;
    }
    for (UIView *child in view.subviews) {
        UIScrollView *pager=NFBDesktopPager(child);
        if (pager) return pager;
    }
    return nil;
}
// An open request is not success: close only once Open reports the target pane.
BOOL NFBLaunchAppFromDesktopIcon(id iconView) {
    NFBDesktopSession *active=session;
    if (!active || active.restoring) return NO;
    if (![iconView isKindOfClass:UIView.class] || ![(UIView *)iconView isDescendantOfView:active.desktop]) return NO;
    if (active.pendingApp.length) return YES;
    id icon=NFBCheckedObject(iconView,@"icon");
    id bundle=NFBCheckedObject(iconView,@"applicationBundleIdentifier");
    if (![bundle isKindOfClass:NSString.class] || ![bundle length])
        bundle=NFBCheckedObject(icon,@"applicationBundleID");
    if (![bundle isKindOfClass:NSString.class] || ![bundle length])
        bundle=NFBCheckedObject(icon,@"applicationBundleIdentifier");
    if (![bundle isKindOfClass:NSString.class] || ![bundle length] || NFBIsSystemDesktop(bundle)) {
        NFBErrorLog(@"desktop split launch: no application identifier for %@",NSStringFromClass([iconView class]));
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"无法读取应用标识，桌面分屏已保留");
        return YES; // Never fall through to a fullscreen launch in the desktop pane.
    }
    active.pendingApp=bundle;
    active.pendingDeadline=CACurrentMediaTime()+8;
    BOOL submitted=!active.startedHome && [active.backgroundApp isEqualToString:bundle]
        ? NFBSplitTrollFrontmostApp() : NFBOpenTrollApp(bundle);
    if (!submitted) {
        active.pendingApp=nil;
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"应用分屏打开失败，桌面分屏已保留");
        NFBErrorLog(@"desktop split launch rejected: %@",bundle);
    }
    return YES;
}
static BOOL NFBDesktopAnimationsEnabled(void) {
    return UIView.areAnimationsEnabled && !UIAccessibilityIsReduceMotionEnabled();
}
static void NFBLogDesktopTouchTree(UIView *view, NSUInteger depth) {
    if (depth > 6) return;
    NFBDebugLog(@"desktop touch tree: depth=%lu class=%@ hidden=%d alpha=%.2f interaction=%d bounds=%@ frame=%@ gestures=%lu",
        (unsigned long)depth, NSStringFromClass(view.class), view.hidden, view.alpha,
        view.userInteractionEnabled, NSStringFromCGRect(view.bounds), NSStringFromCGRect(view.frame),
        (unsigned long)view.gestureRecognizers.count);
    for (UIView *child in view.subviews) NFBLogDesktopTouchTree(child, depth+1);
}
// iOS 16.0.3 device logs show the private root wrapper returning itself for
// every icon/page touch. Only repair that observed blocker, within this session.
// Keep child hit testing native so hidden pages and overlapping views stay excluded.
static UIView *NFBDesktopRepairWrapperHit(UIView *hit, UIWindow *window, CGPoint point, UIEvent *event) {
    if (![NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"])
        return hit;
    for (UIView *child in hit.subviews.reverseObjectEnumerator) {
        UIView *candidate=[child hitTest:[child convertPoint:point fromView:window] withEvent:event];
        if (candidate) return candidate;
    }
    // Device tree shows this wrapper has no children or gestures. It may be a
    // frontmost layout sibling rather than the owner of the interactive content.
    // Search only siblings behind that branch, keeping their native hit tests.
    if (hit.subviews.count==0 && hit.gestureRecognizers.count==0) {
        UIView *branch=hit;
        while (branch && branch!=session.desktop) {
            UIView *parent=branch.superview;
            if (!parent || ![branch isDescendantOfView:session.desktop]) break;
            NSUInteger index=[parent.subviews indexOfObjectIdenticalTo:branch];
            if (index==NSNotFound) break;
            while (index>0) {
                UIView *sibling=parent.subviews[--index];
                UIView *candidate=[sibling hitTest:[sibling convertPoint:point fromView:window] withEvent:event];
                if (candidate && ![NSStringFromClass(candidate.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"])
                    return candidate;
            }
            branch=parent;
        }
    }
    return hit;
}
// Use the native home window: its controller and scene remain the desktop owners.
// This helper is also exercised by the simulator window fixture.
UIView *NFBDesktopSplitHitTest(UIWindow *window, CGPoint point, UIEvent *event, BOOL *handled) {
    NFBDesktopSession *active = session;
    *handled = active && !active.restoring && active.window == window;
    if (!*handled) return nil;
    CGPoint local = [active.panel convertPoint:point fromView:window];
    if (![active.panel pointInside:local withEvent:event]) return nil;
    if (active.refreshScroll) return active.panel;
    if (event) [active activateDesktop];
    UIView *hit = [active.panel hitTest:local withEvent:event];
    UIView *originalHit=hit;
    hit=NFBDesktopRepairWrapperHit(hit,window,point,event);
    if (hit!=originalHit)
        NFBDebugLog(@"desktop wrapper route: %@ -> %@", NSStringFromClass(originalHit.class), NSStringFromClass(hit.class));
    else if ([NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"] && active.blockedHitReports++ < 2)
        NFBLogDesktopTouchTree(active.desktop,0);
    NFBDebugLog(@"desktop native hit: %@", hit ? NSStringFromClass(hit.class) : @"nil");
    return hit;
}
#ifndef NFB_DESKTOP_SIM_TEST
static Class desktopHitClass;
static UIView *(*originalDesktopHitTest)(id, SEL, CGPoint, UIEvent *);
static UIView *NFBDesktopNativeHitTest(id object, SEL selector, CGPoint point, UIEvent *event) {
    BOOL handled = NO;
    UIView *hit = NFBDesktopSplitHitTest(object, point, event, &handled);
    return handled ? hit : originalDesktopHitTest(object, selector, point, event);
}
static BOOL NFBInstallDesktopHitHook(UIWindow *window) {
    Class cls = object_getClass(window);
    if (desktopHitClass) return cls == desktopHitClass;
    Method method = class_getInstanceMethod(cls, @selector(hitTest:withEvent:));
    if (!method) return NO;
    // Hook the actual system window class, including its private hit-test override.
    MSHookMessageEx(cls, @selector(hitTest:withEvent:), (IMP)NFBDesktopNativeHitTest,
                   (IMP *)&originalDesktopHitTest);
    desktopHitClass = cls;
    return originalDesktopHitTest != NULL;
}
#endif
static NSString *lastFailure;
static BOOL failurePending;
NSString *NFBDesktopSplitError(void) { return lastFailure ?: @"桌面分屏打开失败"; }
NSString *NFBConsumeDesktopSplitFailure(void) {
    if (!failurePending) return nil;
    failurePending = NO;
    return NFBDesktopSplitError();
}
static BOOL NFBDesktopFail(NSString *reason) {
    lastFailure = reason;
    NFBErrorLog(@"desktop split: %@", reason);
    return NO;
}

static NSArray<UIWindow *> *NFBDesktopWindows(void) {
    NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    return windows.array;
}
static BOOL NFBDesktopContainsFloating(UIView *view) {
    Class floating = NSClassFromString(@"FloatingAppWindow");
    if (floating && [view isKindOfClass:floating]) return YES;
    for (UIView *child in view.subviews) if (NFBDesktopContainsFloating(child)) return YES;
    return NO;
}
static BOOL NFBDesktopContainsRootFolder(UIView *view) {
    Class root = NSClassFromString(@"SBRootFolderView");
    if (root && [view isKindOfClass:root]) return YES;
    for (UIView *child in view.subviews) if (NFBDesktopContainsRootFolder(child)) return YES;
    return NO;
}
static BOOL NFBDesktopEligible(UIView *view, UIView *anchor) {
    return [view isKindOfClass:UIView.class] && view.superview && ![view isKindOfClass:UIWindow.class] &&
        view != anchor && ![anchor isDescendantOfView:view] && ![view isDescendantOfView:anchor] &&
        NFBDesktopContainsRootFolder(view) && !NFBDesktopContainsFloating(view) &&
        CGRectGetWidth(view.bounds) > 0 && CGRectGetHeight(view.bounds) > 0 &&
        isfinite(CGRectGetWidth(view.bounds)) && isfinite(CGRectGetHeight(view.bounds));
}
static UIView *NFBDesktopFromController(UIViewController *controller, UIView *anchor) {
    if (!controller.isViewLoaded) return nil;
    Class home = NSClassFromString(@"SBHomeScreenViewController");
    if (home && [controller isKindOfClass:home] && NFBDesktopEligible(controller.view, anchor)) return controller.view;
    for (UIViewController *child in controller.childViewControllers) {
        UIView *found = NFBDesktopFromController(child, anchor);
        if (found) return found;
    }
    return nil;
}
static UIView *NFBDesktopContentInTree(UIView *view, UIView *anchor) {
    Class content = NSClassFromString(@"SBIconContentView");
    if (content && [view isKindOfClass:content] && NFBDesktopEligible(view, anchor)) {
        // Never settle for just the icon list: include sibling dock/folder hosts.
        UIView *candidate = view;
        for (UIView *parent=view.superview; parent && ![parent isKindOfClass:UIWindow.class]; parent=parent.superview) {
            if (!NFBDesktopEligible(parent, anchor)) break;
            candidate=parent;
        }
        return candidate;
    }
    for (UIView *child in view.subviews) {
        UIView *found = NFBDesktopContentInTree(child, anchor);
        if (found) return found;
    }
    return nil;
}
// Last-resort lookup, used only after the controller and icon-content routes have
// failed: scan a window for a root folder view and keep its outermost eligible
// ancestor. Covers the case where the desktop is still on screen but no longer
// reachable through the view controller that used to own it.
static UIView *NFBDesktopFromTree(UIView *view, UIView *anchor) {
    Class root = NSClassFromString(@"SBRootFolderView");
    if (root && [view isKindOfClass:root]) {
        UIView *candidate = nil;
        for (UIView *ancestor = view; ancestor && ![ancestor isKindOfClass:UIWindow.class]; ancestor = ancestor.superview) {
            if (!NFBDesktopEligible(ancestor, anchor)) break;
            candidate = ancestor;
        }
        if (candidate) return candidate;
        return NFBDesktopEligible(view, anchor) ? view : nil;
    }
    for (UIView *child in view.subviews) {
        UIView *found = NFBDesktopFromTree(child, anchor);
        if (found) return found;
    }
    return nil;
}
static UIView *NFBDesktopSource(UIView *anchor) {
    // Prefer the complete home controller (dock and folder presentation included).
    for (UIWindow *window in NFBDesktopWindows()) {

        UIView *view = NFBDesktopFromController(window.rootViewController, anchor);
        if (view) return view;
    }
    id icons = NFBCheckedObject(NSClassFromString(@"SBIconController"), @"sharedInstance");
    if ([icons isKindOfClass:UIViewController.class] && [(UIViewController *)icons isViewLoaded]) {
        UIView *view = [(UIViewController *)icons view];
        if (NFBDesktopEligible(view, anchor)) return view;
    }
    for (UIWindow *window in NFBDesktopWindows()) {

        UIView *view = NFBDesktopContentInTree(window, anchor);
        if (view) return view;
    }
    // Fullscreen apps can hide or detach the desktop's original window. Resolve
    // the already loaded root through the native singleton as well as windows.
    id manager = NFBCheckedObject(icons, @"iconManager");
    for (id owner in @[icons ?: NSNull.null, manager ?: NSNull.null]) {
        for (NSString *name in @[@"rootFolderController", @"_rootFolderController"]) {
            id controller = NFBCheckedObject(owner, name);
            if (![controller isKindOfClass:UIViewController.class] || ![(UIViewController *)controller isViewLoaded]) continue;
            UIView *view = [(UIViewController *)controller view];
            UIView *candidate = nil;
            for (UIView *ancestor = view; ancestor && ![ancestor isKindOfClass:UIWindow.class]; ancestor = ancestor.superview) {
                if (!NFBDesktopEligible(ancestor, anchor)) break;
                candidate = ancestor;
            }
            if (candidate) return candidate;
        }
    }
    for (UIWindow *window in NFBDesktopWindows()) {
        UIView *view = NFBDesktopFromTree(window, anchor);
        if (view) {
            NFBErrorLog(@"desktop source resolved by hierarchy scan in %@", NSStringFromClass(window.class));
            return view;
        }
    }
    NFBErrorLog(@"desktop source missing: icons=%@ manager=%@", NSStringFromClass([icons class]), NSStringFromClass([manager class]));
    return nil;
}
static UIView *NFBConstraintView(id item) {
    if ([item isKindOfClass:UIView.class]) return item;
    if ([item isKindOfClass:UILayoutGuide.class]) return [(UILayoutGuide *)item owningView];
    return nil;
}
static BOOL NFBInsideDesktop(UIView *item, UIView *desktop) {
    return item && (item == desktop || [item isDescendantOfView:desktop]);
}
static NSArray<NSLayoutConstraint *> *NFBDesktopExternalConstraints(UIView *desktop) {
    NSMutableArray *result = [NSMutableArray array];
    for (UIView *parent = desktop.superview; parent; parent = parent.superview)
        for (NSLayoutConstraint *constraint in parent.constraints) {
            BOOL first = NFBInsideDesktop(NFBConstraintView(constraint.firstItem), desktop);
            BOOL second = NFBInsideDesktop(NFBConstraintView(constraint.secondItem), desktop);
            if (constraint.active && first != second) [result addObject:constraint];
        }
    return result;
}
static BOOL NFBDesktopLocked(void) {
    id lock = NFBCheckedObject(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance");
    return NFBCheckedBool(lock, @"isUILocked", YES);
}
// The transplanted desktop keeps its icons, folders and widgets: moving the view
// into the pane is what leaves the original home screen showing only its
// wallpaper. What does need help is that SpringBoard hides the home screen's
// content - and its wallpaper - while a fullscreen app is in front, which left
// the pane completely blank. Only the content containers and the wallpaper are
// revealed here, and every change is undone when the pane closes. Individual page
// icon lists are deliberately left alone: only the current page should show.
static BOOL NFBIsDesktopRevealClass(NSString *name) {
    return [name containsString:@"Wallpaper"] || [name containsString:@"SBRootFolder"] ||
        [name containsString:@"IconContent"];
}
static void NFBCollectRevealViews(UIView *view, NSMutableArray<UIView *> *reveal, NSMutableArray<UIView *> *wallpaper) {
    for (UIView *child in view.subviews) {
        NSString *name = NSStringFromClass(child.class);
        BOOL isWallpaper = [name containsString:@"Wallpaper"];
        if (isWallpaper) [wallpaper addObject:child];
        if ((isWallpaper || NFBIsDesktopRevealClass(name)) && (child.hidden || child.alpha < 1))
            [reveal addObject:child];
        NFBCollectRevealViews(child, reveal, wallpaper);
    }
}
static void NFBCountHiddenViews(UIView *view, NSUInteger *count) {
    for (UIView *child in view.subviews) {
        if (child.hidden || child.alpha < 0.01) (*count)++;
        NFBCountHiddenViews(child, count);
    }
}
static UIView *NFBWallpaperInTree(UIView *view) {
    if ([NSStringFromClass(view.class) containsString:@"Wallpaper"] &&
        !view.hidden && view.alpha > 0.01 && CGRectGetWidth(view.bounds) > 1 && CGRectGetHeight(view.bounds) > 1)
        return view;
    for (UIView *child in view.subviews) {
        UIView *found = NFBWallpaperInTree(child);
        if (found) return found;
    }
    return nil;
}
static UIView *NFBSystemWallpaperView(UIWindow *excluding) {
    for (UIWindow *window in NFBDesktopWindows()) {
        if (window == excluding || window.hidden) continue;
        UIView *found = NFBWallpaperInTree(window);
        if (found) return found;
    }
    return nil;
}
@implementation NFBDesktopSession
- (void)refreshWidgetPage {
    if (session!=self || self.restoring || self.startedHome || self.pendingApp.length) return;
    UIScrollView *pager=NFBDesktopPager(self.desktop);
    if (!pager || pager.dragging || pager.decelerating) {
        NFBErrorLog(@"desktop widget page refresh: no idle horizontal pager"); return;
    }
    CGPoint original=pager.contentOffset;
    CGFloat width=pager.bounds.size.width;
    CGFloat minimum=-pager.adjustedContentInset.left;
    CGFloat maximum=pager.contentSize.width-width+pager.adjustedContentInset.right;
    CGFloat target=original.x+width<=maximum+0.5 ? MIN(maximum,original.x+width) : MAX(minimum,original.x-width);
    if (fabs(target-original.x)<width*0.5) return;
    self.refreshScroll=pager; self.refreshOffset=original;
    UIView *cover=[self.canvas snapshotViewAfterScreenUpdates:NO];
    cover.frame=self.canvas.bounds; cover.userInteractionEnabled=NO;
    self.refreshCover=cover; if (cover) [self.canvas addSubview:cover];
    // Reproduce the device-proven page exit/reentry, with the original page
    // covered and its exact offset restored before exposing the refreshed pane.
    [UIView performWithoutAnimation:^{
        [pager setContentOffset:CGPointMake(target,original.y) animated:NO];
        [pager layoutIfNeeded];
    }];
    __weak NFBDesktopSession *weakSession=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.1*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        NFBDesktopSession *active=weakSession;
        if (!active || session!=active || active.restoring) return;
        [UIView performWithoutAnimation:^{
            [pager setContentOffset:original animated:NO];
            [pager layoutIfNeeded];
        }];
        [active.refreshCover removeFromSuperview]; active.refreshCover=nil;
        active.refreshScroll=nil;
        NFBDebugLog(@"desktop widget page refresh: restored %@ offset=%@",NSStringFromClass(pager.class),NSStringFromCGPoint(original));
    });
}
- (void)activateDesktop {
    if (self.restoring) return;
    [self adoptDesktopInteraction];
    if (!self.window.isKeyWindow) [self.window makeKeyWindow];
}
- (void)rememberAppearance:(UIView *)view {
    [self.appearanceViews addObject:view];
    [self.appearanceHidden addObject:@(view.hidden)];
    [self.appearanceAlpha addObject:@(view.alpha)];
}
- (void)adoptDesktopAppearance {
    NSMutableArray<UIView *> *reveal = [NSMutableArray array];
    NSMutableArray<UIView *> *wallpaper = [NSMutableArray array];
    NFBCollectRevealViews(self.desktop, reveal, wallpaper);
    self.appearanceViews = [NSMutableArray array];
    self.appearanceHidden = [NSMutableArray array];
    self.appearanceAlpha = [NSMutableArray array];
    for (UIView *view in reveal) {
        [self rememberAppearance:view];
        view.hidden = NO;
        view.alpha = 1;
    }
    self.wallpaperCount = wallpaper.count;
    NSUInteger hidden = 0;
    NFBCountHiddenViews(self.desktop, &hidden);
    NFBDebugLog(@"desktop pane: revealed %lu view(s), wallpaper=%lu, still hidden=%lu",
        (unsigned long)reveal.count, (unsigned long)wallpaper.count, (unsigned long)hidden);
}
- (void)restoreDesktopAppearance {
    for (NSUInteger index = 0; index < self.appearanceViews.count; index++) {
        UIView *view = self.appearanceViews[index];
        view.hidden = self.appearanceHidden[index].boolValue;
        view.alpha = self.appearanceAlpha[index].doubleValue;
    }
    self.appearanceViews = nil; self.appearanceHidden = nil; self.appearanceAlpha = nil;
}
- (void)installPaneBackdrop {
    // The desktop subtree carries no wallpaper of its own, so borrow one: a
    // snapshot of the live system wallpaper when it is on screen, otherwise a
    // material, so the pane never shows a bare light background.
    UIView *backdrop = nil;
    UIView *wallpaper = NFBSystemWallpaperView(self.window);
    if (wallpaper) {
        UIView *snapshot = [wallpaper snapshotViewAfterScreenUpdates:NO];
        if (snapshot) {
            snapshot.frame = self.canvas.bounds;
            snapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            snapshot.userInteractionEnabled = NO;
            backdrop = snapshot;
        }
    }
    if (!backdrop) {
        UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        material.frame = self.canvas.bounds;
        material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        backdrop = material;
    }
    backdrop.userInteractionEnabled = NO;
    self.paneBackdrop = backdrop;
    [self.canvas insertSubview:backdrop atIndex:0];
    NFBDebugLog(@"desktop pane: backdrop installed (%@)", NSStringFromClass(backdrop.class));
}
- (void)adoptDesktopInteraction {
    if (!self.interactionViews) { self.interactionViews = [NSMutableArray array]; self.interactionValues = [NSMutableArray array]; }
    if (!self.scrollViews) { self.scrollViews = [NSMutableArray array]; self.scrollValues = [NSMutableArray array]; }
    if (!self.touchGestures) { self.touchGestures = [NSMutableArray array]; self.gestureValues = [NSMutableArray array]; }
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:self.desktop];
    while (stack.count) {
        UIView *view = stack.lastObject; [stack removeLastObject];
        if (view.hidden || view.alpha < 0.01) continue; // Never expose offscreen pages.
        [stack addObjectsFromArray:view.subviews];
        BOOL target = [view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UIControl.class] ||
            [NSStringFromClass(view.class) containsString:@"IconView"] || view.gestureRecognizers.count > 0;
        if (!target) continue;
        for (UIView *ancestor=view; ancestor && ancestor != self.canvas; ancestor=ancestor.superview) {
            if (!ancestor.userInteractionEnabled) {
                if (![self.interactionViews containsObject:ancestor]) {
                    [self.interactionViews addObject:ancestor]; [self.interactionValues addObject:@NO];
                }
                ancestor.userInteractionEnabled=YES;
            }
        }
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll=(UIScrollView *)view;
            if (![self.scrollViews containsObject:scroll]) {
                [self.scrollViews addObject:scroll]; [self.scrollValues addObject:@(scroll.scrollEnabled)];
            }
            scroll.scrollEnabled=YES;
        }
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            if (!gesture.enabled && ([gesture isKindOfClass:UITapGestureRecognizer.class] ||
                ([view isKindOfClass:UIScrollView.class] && gesture == [(UIScrollView *)view panGestureRecognizer]))) {
                if (![self.touchGestures containsObject:gesture]) {
                    [self.touchGestures addObject:gesture]; [self.gestureValues addObject:@NO];
                }
                gesture.enabled=YES;
            }
        }
    }

}
- (void)restoreDesktopInteraction {
    for (NSUInteger i=0;i<self.touchGestures.count;i++) self.touchGestures[i].enabled=self.gestureValues[i].boolValue;
    for (NSUInteger i=0;i<self.scrollViews.count;i++) self.scrollViews[i].scrollEnabled=self.scrollValues[i].boolValue;
    for (NSUInteger i=0;i<self.interactionViews.count;i++) self.interactionViews[i].userInteractionEnabled=self.interactionValues[i].boolValue;
    self.interactionViews=nil; self.interactionValues=nil; self.scrollViews=nil; self.scrollValues=nil;
    self.touchGestures=nil; self.gestureValues=nil;
}
- (BOOL)place {
    UIWindow *window = self.window;
    CGRect screen = window.bounds;
    if (CGRectGetWidth(screen) >= CGRectGetHeight(screen)) return NFBDesktopFail(@"桌面分屏目前仅支持竖屏");
    if (!self.placed) {
        UIView *anchor = self.anchor;
        if (!anchor.window) return NFBDesktopFail(@"原分屏窗口已关闭");
        // The pane reproduces the split app pane exactly: same size, same position.
        // The anchor is itself a window, so convert straight into the pane window; a
        // window-to-itself conversion would silently drop the origin.
        CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:window];
        if (!isfinite(anchorFrame.origin.x) || !isfinite(anchorFrame.origin.y) ||
            !isfinite(CGRectGetWidth(anchorFrame)) || !isfinite(CGRectGetHeight(anchorFrame)) ||
            CGRectGetWidth(anchorFrame) < 120 || CGRectGetHeight(anchorFrame) < 180)
            return NFBDesktopFail(@"原分屏窗口尺寸无效");
        self.panelFrame = anchorFrame;
        self.placed = YES;
    }
    CGRect frame = self.panelFrame;
    frame.origin.x = MAX(CGRectGetMinX(screen), MIN(frame.origin.x, CGRectGetMaxX(screen)-frame.size.width));
    frame.origin.y = MAX(CGRectGetMinY(screen), MIN(frame.origin.y, CGRectGetMaxY(screen)-frame.size.height));
    self.panelFrame = frame;
    CGRect panelBounds = CGRectMake(0,0,frame.size.width,frame.size.height);
    CGPoint panelCenter = CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    if (!CGRectEqualToRect(self.panel.bounds,panelBounds)) self.panel.bounds = panelBounds;
    if (!CGPointEqualToPoint(self.panel.center,panelCenter)) self.panel.center = panelCenter;
    // The wallpaper fills the whole pane; the header floats above it.
    self.canvas.frame = self.panel.bounds;
    double scale = NFBDesktopScale(CGRectGetWidth(self.originalBounds), CGRectGetHeight(self.originalBounds),
        CGRectGetWidth(self.canvas.bounds),CGRectGetHeight(self.canvas.bounds));
    if (!(scale > 0)) return NFBDesktopFail(@"桌面尺寸无效");
    if (self.desktop.superview == self.canvas) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.canvas.bounds),CGRectGetMidY(self.canvas.bounds));
        CGAffineTransform transform = CGAffineTransformMakeScale(scale,scale);
        if (!CGRectEqualToRect(self.desktop.bounds,self.originalBounds)) self.desktop.bounds = self.originalBounds;
        if (!CGPointEqualToPoint(self.desktop.center,center)) self.desktop.center = center;
        if (!CGAffineTransformEqualToTransform(self.desktop.transform,transform)) self.desktop.transform = transform;
        self.desktop.hidden = NO; self.desktop.alpha = 1; self.desktop.userInteractionEnabled = YES;
    }
    return YES;
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.dragStart = self.panelFrame.origin;
    CGPoint translation = [gesture translationInView:self.window];
    CGRect frame = self.panelFrame;
    frame.origin = CGPointMake(self.dragStart.x+translation.x,self.dragStart.y+translation.y);
    self.panelFrame = frame;
    [self place];
}
- (void)closePressed { NFBCloseDesktopSplit(); }
- (void)check {
    if (session != self || self.restoring) return;
    if (NFBDesktopLocked()) {
        NFBCloseDesktopSplit(); return;
    }
    if (self.pendingApp.length) {
        NFBInvalidateWindowState();
        NFBWindowState *state=NFBCurrentWindowState();
        if ([state.floatingApp isEqualToString:self.pendingApp] && state.floatingWindow && !state.mini) {
            NFBDebugLog(@"desktop split launch visible: %@",self.pendingApp);
            NFBCloseDesktopSplit(); return;
        }
        if (CACurrentMediaTime()>=self.pendingDeadline) {
            NFBErrorLog(@"desktop split launch timed out: %@",self.pendingApp);
            self.pendingApp=nil;
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"尚未确认应用分屏打开，桌面分屏已保留");
        }
    }
    if (self.desktop.superview != self.canvas || ![self place]) {
        if (self.desktop.superview != self.canvas) NFBDesktopFail(@"系统重新调整了桌面视图，已恢复桌面");
        failurePending = YES; NFBCloseDesktopSplit();
        return;
    }
    if (self.window.hidden || self.window.alpha < 0.01) {
        NFBDesktopFail(@"系统隐藏了原生桌面窗口，已恢复桌面");
        failurePending = YES; NFBCloseDesktopSplit(); return;
    }
    // Repair native interaction changes without overwriting the original state.
    [self adoptDesktopInteraction];
}
- (void)restore {
    if (self.restoring) return;
    self.restoring = YES;
    [self.timer invalidate]; self.timer = nil;
    if (self.refreshScroll) [self.refreshScroll setContentOffset:self.refreshOffset animated:NO];
    self.refreshScroll=nil; [self.refreshCover removeFromSuperview]; self.refreshCover=nil;
    [self restoreDesktopInteraction];
    if (self.suppliedAppearance) {
        [self.desktopController beginAppearanceTransition:NO animated:NO];
        [self.desktopController endAppearanceTransition];
        self.suppliedAppearance=NO;
    }
    [self restoreDesktopAppearance];
    UIView *view = self.desktop;
    if (self.mutated && view && self.originalParent) {
        [view removeFromSuperview];
        view.transform = CGAffineTransformIdentity;
        view.bounds = self.originalBounds; view.center = self.originalCenter;
        view.autoresizingMask = self.originalAutoresizing;
        view.translatesAutoresizingMaskIntoConstraints = self.originalTranslates;
        view.hidden = self.originalHidden; view.alpha = self.originalAlpha;
        view.userInteractionEnabled = self.originalInteraction;
        [self.originalParent insertSubview:view atIndex:MIN(self.originalIndex, self.originalParent.subviews.count)];
        view.transform = self.originalTransform;
        [NSLayoutConstraint activateConstraints:self.constraints];
        [self.originalParent setNeedsLayout];
        [self.originalParent layoutIfNeeded];
    }
    [self.panel removeFromSuperview];
    [self.backgroundFrost removeFromSuperview];
    if (self.windowMutated) {
        for (NSUInteger i=0; i<self.windowSiblings.count; i++)
            self.windowSiblings[i].hidden=self.windowSiblingHidden[i].boolValue;
        self.window.backgroundColor=self.originalWindowColor;
        self.window.opaque=self.originalWindowOpaque;
        self.window.windowLevel = self.originalWindowLevel;
        self.window.alpha = self.originalWindowAlpha;
        self.window.userInteractionEnabled = self.originalWindowInteraction;
        self.window.hidden = self.originalWindowHidden;
        if (self.window.isKeyWindow && self.previousKeyWindow && !self.previousKeyWindow.hidden)
            [self.previousKeyWindow makeKeyWindow];
    }
    self.backgroundFrost = nil;
    self.window = nil; self.desktop = nil; self.originalParent = nil; self.constraints = nil;
    NFBInvalidateWindowState();
}
@end
BOOL NFBDesktopSplitActive(void) { return session != nil && !session.restoring; }
void NFBCloseDesktopSplit(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NFBCloseDesktopSplit(); }); return; }
    NFBDesktopSession *closing = session;
    session = nil;
    @try { [closing restore]; }
    @catch (NSException *exception) { NFBErrorLog(@"desktop restore failed: %@", exception); }
}
void NFBUpdateDesktopSplit(BOOL allowed) {
    if (!NSThread.isMainThread) return;
    if (!allowed) NFBCloseDesktopSplit();
    else [session check];
}
#ifndef NFB_DESKTOP_SIM_TEST
static void (*originalLaunchIcon)(id, SEL, id, id);
static void NFBDesktopLaunchIcon(id object, SEL selector, id icon, id actions) {
    if (NFBLaunchAppFromDesktopIcon(icon)) return;
    originalLaunchIcon(object,selector,icon,actions);
}
static BOOL NFBInstallDesktopLaunchHook(void) {
    static BOOL installed;
    if (installed) return YES;
    Class cls = NSClassFromString(@"SBIconController");
    SEL selector = NSSelectorFromString(@"_launchFromIconView:withActions:");
    Method method = class_getInstanceMethod(cls,selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 4 || strcmp(signature.methodReturnType,"v") ||
        [signature getArgumentTypeAtIndex:2][0] != '@' || [signature getArgumentTypeAtIndex:3][0] != '@') return NO;
    MSHookMessageEx(cls,selector,(IMP)NFBDesktopLaunchIcon,(IMP *)&originalLaunchIcon);
    installed = YES;
    return YES;
}
#endif
BOOL NFBShowDesktopInSplit(UIView *anchor) {
    if (!NSThread.isMainThread) return NO;
    lastFailure = nil; failurePending = NO;
    if (!anchor.window) return NFBDesktopFail(@"没有可用的分屏窗口");
    if (NFBDesktopLocked()) return NFBDesktopFail(@"锁屏时不能打开桌面分屏");
    if (session) { NFBCloseDesktopSplit(); return YES; }
    NFBDesktopSession *next = [NFBDesktopSession new];
    @try {
        NFBUpdateDesktopFreeze(NO, 0);
        UIView *desktop = NFBDesktopSource(anchor);
        if (!desktop) return NFBDesktopFail(@"没有找到已加载的系统桌面视图");
        NFBWindowState *state = NFBCurrentWindowState();
        next.startedHome = state.home; next.backgroundApp = state.frontApp;
        next.desktop = desktop; next.originalParent = desktop.superview; next.anchor = anchor;
        next.originalIndex = [desktop.superview.subviews indexOfObjectIdenticalTo:desktop];
        next.originalBounds = desktop.bounds; next.originalCenter = desktop.center;
        next.originalTransform = desktop.transform; next.originalAutoresizing = desktop.autoresizingMask;
        next.originalTranslates = desktop.translatesAutoresizingMaskIntoConstraints;
        next.originalHidden = desktop.hidden; next.originalInteraction = desktop.userInteractionEnabled;
        next.originalAlpha = desktop.alpha; next.constraints = NFBDesktopExternalConstraints(desktop);
        UIWindow *window = desktop.window;
        if (!window) return NFBDesktopFail(@"原生桌面窗口尚未加载，请先返回主屏幕再打开");
#ifndef NFB_DESKTOP_SIM_TEST
        if (!NFBInstallDesktopHitHook(window)) return NFBDesktopFail(@"原生桌面窗口触摸接口不可用");
        if (!NFBInstallDesktopLaunchHook()) return NFBDesktopFail(@"桌面应用分屏启动接口不可用");
#endif
        next.window = window;
        next.desktopController=NFBDesktopOwner(window.rootViewController,desktop);
        next.originalWindowLevel = window.windowLevel;
        next.originalWindowAlpha = window.alpha;
        next.originalWindowHidden = window.hidden;
        next.originalWindowInteraction = window.userInteractionEnabled;
        next.originalWindowColor = window.backgroundColor;
        next.originalWindowOpaque = window.opaque;
        for (UIWindow *candidate in NFBDesktopWindows())
            if (candidate.isKeyWindow) { next.previousKeyWindow = candidate; break; }
        // No new UIWindow or scene; do not replace the native root controller.
        UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
        panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
        panel.layer.cornerRadius = 14; panel.clipsToBounds = YES;
        next.panel = panel; [window addSubview:panel];
        // Clear so the wallpaper - from the desktop subtree or borrowed below -
        // shows through instead of a flat system background.
        UIView *canvas = [UIView new]; canvas.backgroundColor = UIColor.clearColor;
        canvas.clipsToBounds = YES; next.canvas = canvas; [panel addSubview:canvas];
        // Verify geometry before touching the desktop hierarchy.
        if (![next place]) { next.desktop = nil; return NO; }
        if (next.startedHome) {
            UIVisualEffectView *frost = [[UIVisualEffectView alloc] initWithEffect:nil];
            frost.frame = [desktop convertRect:desktop.bounds toView:next.originalParent];
            frost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            frost.contentView.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.25];
            [next.originalParent insertSubview:frost atIndex:next.originalIndex];
            next.backgroundFrost = frost;
        }
        next.mutated = YES;
        [NSLayoutConstraint deactivateConstraints:next.constraints];
        desktop.translatesAutoresizingMaskIntoConstraints = YES; desktop.autoresizingMask = UIViewAutoresizingNone;
        [canvas addSubview:desktop];
        if (![next place]) { [next restore]; return NO; }
        // The pane keeps the desktop's icons, folders and widgets; only the
        // wallpaper is forced on screen, and supplied when the subtree has none.
        [next adoptDesktopAppearance];
        [next adoptDesktopInteraction];
        if (next.wallpaperCount == 0) [next installPaneBackdrop];
        session = next;
        next.windowMutated = YES;
        // Raising the native window must not raise its fullscreen siblings over
        // the app behind the pane. Save them so close restores the native tree.
        next.windowSiblings=[NSMutableArray array];
        next.windowSiblingHidden=[NSMutableArray array];
        for (UIView *sibling in window.subviews) {
            if (sibling==panel) continue;
            [next.windowSiblings addObject:sibling];
            [next.windowSiblingHidden addObject:@(sibling.hidden)];
            sibling.hidden=YES;
        }
        window.backgroundColor=UIColor.clearColor; window.opaque=NO;
        window.windowLevel = MAX(anchor.window.windowLevel + 2, UIWindowLevelStatusBar + 1);
        window.alpha = 1; window.userInteractionEnabled = YES; window.hidden = NO;
        [window bringSubviewToFront:panel];
        [next activateDesktop];
        if (!next.startedHome && next.desktopController) {
            // Fullscreen apps leave the home controller disappeared. Moving its
            // view alone does not resume widget child controllers/render hosts.
            next.suppliedAppearance=YES;
            [next.desktopController beginAppearanceTransition:YES animated:NO];
            [next.desktopController endAppearanceTransition];
            [desktop setNeedsLayout]; [desktop layoutIfNeeded];
            __weak NFBDesktopSession *refreshSession=next;
            dispatch_async(dispatch_get_main_queue(), ^{
                NFBDesktopSession *active=refreshSession;
                if (active && session==active && !active.restoring) {
                    [active.desktop setNeedsLayout]; [active.desktop layoutIfNeeded];
                    [active refreshWidgetPage];
                    NFBDebugLog(@"desktop widget appearance refreshed for fullscreen background");
                }
            });
        }
        next.timer = [NSTimer timerWithTimeInterval:0.1 target:next selector:@selector(check) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:next.timer forMode:NSRunLoopCommonModes];
        if (NFBDesktopAnimationsEnabled()) {
            panel.alpha = 0; panel.transform = CGAffineTransformMakeScale(0.94,0.94);
            [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                panel.alpha = 1; panel.transform = CGAffineTransformIdentity;
                next.backgroundFrost.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            } completion:nil];
        } else next.backgroundFrost.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        NFBErrorLog(@"desktop native host: view=%@ window=%@ root=%@ sameScene=%d pane=%@",
            NSStringFromClass(desktop.class), NSStringFromClass(window.class),
            NSStringFromClass(window.rootViewController.class), desktop.window==window,
            NSStringFromCGRect(next.panelFrame));
        return YES;
    } @catch (NSException *exception) {
        NSArray<NSString *> *frames = exception.callStackSymbols ?: @[];
        NSUInteger keep = MIN(frames.count, (NSUInteger)8);
        NFBDesktopFail([NSString stringWithFormat:@"桌面承载异常：%@ %@ %@", exception.name,
            exception.reason ?: @"", [[frames subarrayWithRange:NSMakeRange(0, keep)] componentsJoinedByString:@" <- "]]);
        if (session == next) session = nil;
        [next restore];
        return NO;
    }
}
