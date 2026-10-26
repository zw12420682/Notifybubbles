#import "NFBDesktopHost.h"
#import "NFBDesktopGeometry.h"
#import "NFBInterfaces.h"
#import "NFBWindowState.h"
#import "NFBSystemDesktop.h"
#import "NFBDebugLog.h"
#import "NFBPrivacy.h"
#import "NFBTrollOpen.h"
#import "NFBStateLedger.h"
#import <QuartzCore/QuartzCore.h>
#ifndef NFB_DESKTOP_SIM_TEST
#import <substrate.h>
#endif
#include <math.h>

@interface NFBDesktopSession : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIView *canvas;
@property(nonatomic, strong) UIView *desktopHost;
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
@property(nonatomic) NSUInteger wallpaperCount;
@property(nonatomic,strong) NFBStateLedger *appearanceState, *interactionState, *siblingState;
@property(nonatomic) CFTimeInterval lastInteractionScan;
@property(nonatomic,strong) NSHashTable<UIView *> *knownInteractiveViews;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic) CGFloat originalWindowLevel, originalWindowAlpha;
@property(nonatomic) BOOL originalWindowHidden, originalWindowInteraction, windowMutated;
@property(nonatomic,strong) UIColor *originalWindowColor;
@property(nonatomic) BOOL originalWindowOpaque;
@property(nonatomic) NSUInteger blockedHitReports;
@property(nonatomic,strong) UIViewController *desktopController;
@property(nonatomic) BOOL suppliedAppearance;
@property(nonatomic,copy) NSString *pendingApp;
@property(nonatomic) CFTimeInterval pendingDeadline;
@property(nonatomic,strong) UIScrollView *refreshScroll;
@property(nonatomic) CGPoint refreshOffset;
@property(nonatomic,strong) UIView *refreshCover;
- (void)refreshWidgetPage;
- (void)finishWidgetRefresh;
- (void)activateDesktop;
- (void)adoptDesktopInteraction;
- (void)restoreDesktopInteraction;
@property(nonatomic) BOOL startedHome;
@property(nonatomic) CGRect panelFrame;
@property(nonatomic) BOOL placed;
@property(nonatomic) BOOL restoring, mutated;
- (BOOL)place;
- (void)check;
- (void)checkBody;
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
static UIScrollView *NFBFindIconPager(UIView *view) {
    if (view.hidden || view.alpha<0.01) return nil;
    NSString *name=NSStringFromClass(view.class);
    if ([name containsString:@"Folder"] && ![name containsString:@"RootFolder"]) return nil;
    if ([view isKindOfClass:UIScrollView.class] && [name containsString:@"IconScroll"])
        return (UIScrollView *)view;
    for (UIView *child in view.subviews) {
        UIScrollView *pager=NFBFindIconPager(child); if (pager) return pager;
    }
    return nil;
}
static UIScrollView *NFBDesktopPager(UIView *desktop) {
    UIScrollView *pager=NFBFindIconPager(desktop);
    if (pager) return pager;
    for (UIView *view in desktop.subviews)
        if (!view.hidden && view.alpha>=0.01 && [view isKindOfClass:UIScrollView.class] && [(UIScrollView *)view isPagingEnabled])
            return (UIScrollView *)view;
    return nil;
}
// An open request is not success: close only once Open reports the target pane.
BOOL NFBLaunchAppFromDesktopIcon(id iconView) {
    NFBDesktopSession *active=session;
    if (!active || active.restoring) return NO;
    if (![iconView isKindOfClass:UIView.class] || ![(UIView *)iconView isDescendantOfView:active.desktop]) return NO;
    id icon=NFBCheckedObject(iconView,@"icon");
    Class folderClass=NSClassFromString(@"SBFolderIcon");
    if (NFBCheckedBool(iconView,@"isFolderIcon",NO) || NFBCheckedBool(icon,@"isFolderIcon",NO) ||
        (folderClass && [icon isKindOfClass:folderClass])) {
        NFBDebugLog(@"desktop folder icon: native folder handling");
        return NO; // The hook calls the original folder handler; no app launch.
    }
    if (active.pendingApp.length) return YES;
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
    NFBInvalidateWindowState();
    NFBWindowState *current=NFBCurrentWindowState();
    BOOL submitted=!current.home && [current.frontApp isEqualToString:bundle]
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
static void NFBLogDesktopTouchTree(UIView *view, NSUInteger depth, NSUInteger *remaining) {
    if (!NFBDebugLoggingEnabled() || depth > 6 || !*remaining) return;
    --*remaining;
    NFBDebugLog(@"desktop touch tree: depth=%lu class=%@ hidden=%d alpha=%.2f interaction=%d bounds=%@ frame=%@ gestures=%lu",
        (unsigned long)depth, NSStringFromClass(view.class), view.hidden, view.alpha,
        view.userInteractionEnabled, NSStringFromCGRect(view.bounds), NSStringFromCGRect(view.frame),
        (unsigned long)view.gestureRecognizers.count);
    for (UIView *child in view.subviews) NFBLogDesktopTouchTree(child, depth+1, remaining);
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
    // Activating swaps the key window and BFS-scans the desktop subtree. Doing it
    // inside hit-test changes the responder chain mid-dispatch and stalls the
    // first touch; hand it to the next runloop turn instead.
    if (event) {
        static NSUInteger scheduledActivation;
        if (!scheduledActivation) {
            scheduledActivation++;
            dispatch_async(dispatch_get_main_queue(), ^{
                scheduledActivation = 0;
                NFBDesktopSession *current = session;
                if (current && !current.restoring && current.window == window) [current activateDesktop];
            });
        }
    }
    UIView *hit = [active.panel hitTest:local withEvent:event];
    UIView *originalHit=hit;
    hit=NFBDesktopRepairWrapperHit(hit,window,point,event);
    if ([NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"]) {
        // A freshly exposed page may contain new disabled descendants. Repair
        // that observed miss immediately rather than waiting for the next scan.
        active.lastInteractionScan=0; [active adoptDesktopInteraction];
        hit=[active.panel hitTest:local withEvent:event];
        hit=NFBDesktopRepairWrapperHit(hit,window,point,event);
    }
    if (NFBDebugLoggingEnabled()) {
        if (hit!=originalHit)
            NFBDebugLog(@"desktop wrapper route: %@ -> %@",NSStringFromClass(originalHit.class),NSStringFromClass(hit.class));
        else if ([NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"] && active.blockedHitReports++ < 2) {
            NSUInteger remaining=80; NFBLogDesktopTouchTree(active.desktop,0,&remaining);
        }
        NFBDebugLog(@"desktop native hit: %@",hit ? NSStringFromClass(hit.class) : @"nil");
    }
    return hit;
}
// Device traces show this close-only match-move animation displacing the
// folder container while its model geometry and the pane host stay fixed.
// Its screen-space tracking is invalid after transplanting the native desktop.
// Preserve all native scale/opacity animations and the ordinary home screen.
BOOL NFBDesktopSuppressFolderTracking(CALayer *layer, NSString *key) {
    NFBDesktopSession *active=session;
    if (!NSThread.isMainThread || !active || active.restoring ||
        ![key isEqualToString:@"SBFolderSourceViewTrackingMatchMoveAnimation"]) return NO;
    Class containerClass=NSClassFromString(@"SBFolderContainerView");
    id owner=layer.delegate;
    if (!containerClass || ![owner isKindOfClass:containerClass] ||
        ![owner isKindOfClass:UIView.class] || [(UIView *)owner layer]!=layer ||
        ![(UIView *)owner isDescendantOfView:active.desktop]) return NO;
    for (CALayer *ancestor=layer; ancestor; ancestor=ancestor.superlayer)
        if (ancestor==active.desktop.layer) return YES;
    return NO;
}
#ifndef NFB_DESKTOP_SIM_TEST
static void (*originalDesktopAddAnimation)(CALayer *, SEL, CAAnimation *, NSString *);
static void NFBDesktopAddAnimation(CALayer *layer, SEL selector, CAAnimation *animation, NSString *key) {
    if (NFBDesktopSuppressFolderTracking(layer,key)) {
        NFBDebugLog(@"desktop folder close: bypass screen-space source tracking");
        return;
    }
    originalDesktopAddAnimation(layer,selector,animation,key);
}
static void NFBInstallDesktopFolderAnimationHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MSHookMessageEx(CALayer.class,@selector(addAnimation:forKey:),(IMP)NFBDesktopAddAnimation,(IMP *)&originalDesktopAddAnimation);
    });
}
#endif
#ifndef NFB_DESKTOP_SIM_TEST
static Class desktopHitClass;
static UIView *(*originalDesktopHitTest)(id, SEL, CGPoint, UIEvent *);
static UIView *NFBDesktopNativeHitTest(id object, SEL selector, CGPoint point, UIEvent *event) {
    // Touch path: an exception escaping here unwinds through UIKit's event
    // dispatch and kills SpringBoard. Always fall back to the native result.
    BOOL handled = NO;
    @try {
        UIView *hit = NFBDesktopSplitHitTest(object, point, event, &handled);
        if (handled) return hit;
    } @catch (NSException *error) {
        NFBErrorLog(@"desktop hit test failed: %@", error);
    }
    return originalDesktopHitTest(object, selector, point, event);
}
static BOOL NFBInstallDesktopHitHook(UIWindow *window) {
    Class cls = object_getClass(window);
    if (desktopHitClass) return cls == desktopHitClass && originalDesktopHitTest != NULL;
    Method method = class_getInstanceMethod(cls, @selector(hitTest:withEvent:));
    if (!method) return NO;
    NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (sig.numberOfArguments!=4 || sig.methodReturnType[0]!='@' ||
        strcmp([sig getArgumentTypeAtIndex:2],@encode(CGPoint)) || [sig getArgumentTypeAtIndex:3][0]!='@') return NO;
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
    Class floating = NFBTrollFloatingWindowClass();
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
    NSArray<UIWindow *> *windows=NFBDesktopWindows();
    // Prefer the complete home controller (dock and folder presentation included).
    for (UIWindow *window in windows) {

        UIView *view = NFBDesktopFromController(window.rootViewController, anchor);
        if (view) return view;
    }
    id icons = NFBCheckedObject(NSClassFromString(@"SBIconController"), @"sharedInstance");
    if ([icons isKindOfClass:UIViewController.class] && [(UIViewController *)icons isViewLoaded]) {
        UIView *view = [(UIViewController *)icons view];
        if (NFBDesktopEligible(view, anchor)) return view;
    }
    for (UIWindow *window in windows) {

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
    for (UIWindow *window in windows) {
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
- (void)finishWidgetRefresh {
    UIScrollView *pager=self.refreshScroll; CGPoint offset=self.refreshOffset;
    NFBAttemptCleanup(@"widget page offset", ^{
        if (pager) [UIView performWithoutAnimation:^{ [pager setContentOffset:offset animated:NO]; [pager layoutIfNeeded]; }];
    });
    self.refreshScroll=nil;
    NFBAttemptCleanup(@"widget cover", ^{ [self.refreshCover removeFromSuperview]; }); self.refreshCover=nil;
}
- (void)refreshWidgetPage {
    @try {
    if (session!=self || self.restoring || self.startedHome || self.pendingApp.length) return;
    UIScrollView *pager=NFBDesktopPager(self.desktop);
    if (!pager || pager.dragging || pager.decelerating) {
        NFBDebugLog(@"desktop widget page refresh: no idle horizontal pager"); return;
    }
    if (pager.contentSize.width<pager.bounds.size.width*2 || pager.bounds.size.width<=0) {
        NFBDebugLog(@"desktop widget refresh: only one reachable page; no page roundtrip"); return;
    }
    CGPoint original=pager.contentOffset;
    CGFloat width=pager.bounds.size.width;
    CGFloat minimum=-pager.adjustedContentInset.left;
    CGFloat maximum=pager.contentSize.width-width+pager.adjustedContentInset.right;
    CGFloat target=original.x+width<=maximum+0.5 ? MIN(maximum,original.x+width) : MAX(minimum,original.x-width);
    if (fabs(target-original.x)<width*0.5) return;
    UIView *cover=[self.canvas snapshotViewAfterScreenUpdates:NO];
    if (!cover) {
        // A newly attached host may not yet have a compositor snapshot.
        // Render the existing layer tree as a cover without forcing a screen
        // update or giving up the page refresh altogether.
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.canvas.bounds];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [self.canvas.layer renderInContext:context.CGContext];
        }];
        if (image) cover=[[UIImageView alloc] initWithImage:image];
    }
    if (!cover) { NFBErrorLog(@"desktop widget refresh: both cover capture paths failed; page preserved"); return; }
    self.refreshScroll=pager; self.refreshOffset=original;
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
        [active finishWidgetRefresh];
        NFBDebugLog(@"desktop widget page refresh: restored %@ offset=%@",NSStringFromClass(pager.class),NSStringFromCGPoint(original));
    });
    } @catch (NSException *error) {
        [self finishWidgetRefresh]; NFBErrorLog(@"desktop widget refresh failed: %@",error);
    }
}
- (void)activateDesktop {
    if (self.restoring) return;
    [self adoptDesktopInteraction];
    if (!self.window.isKeyWindow) [self.window makeKeyWindow];
}
- (void)rememberAppearance:(UIView *)view {
    if (!self.appearanceState) self.appearanceState=[NFBStateLedger new];
    BOOL hidden=view.hidden; CGFloat alpha=view.alpha;
    [self.appearanceState remember:view key:@"appearance" restore:^{ view.hidden=hidden; view.alpha=alpha; }];
}
- (void)adoptDesktopAppearance {
    NSMutableArray<UIView *> *reveal = [NSMutableArray array];
    NSMutableArray<UIView *> *wallpaper = [NSMutableArray array];
    NFBCollectRevealViews(self.desktop, reveal, wallpaper);
    for (UIView *view in reveal) {
        [self rememberAppearance:view];
        view.hidden = NO;
        view.alpha = 1;
    }
    self.wallpaperCount = wallpaper.count;
    if (NFBDebugLoggingEnabled()) {
        NSUInteger hidden=0; NFBCountHiddenViews(self.desktop,&hidden);
        NFBDebugLog(@"desktop pane: revealed %lu view(s), wallpaper=%lu, still hidden=%lu",
            (unsigned long)reveal.count,(unsigned long)wallpaper.count,(unsigned long)hidden);
    }
}
- (void)restoreDesktopAppearance { [self.appearanceState restore]; self.appearanceState=nil; }
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
    [self.canvas insertSubview:backdrop atIndex:0];
    NFBDebugLog(@"desktop pane: backdrop installed (%@)", NSStringFromClass(backdrop.class));
}
- (void)adoptDesktopInteraction {
    if (!self.interactionState) self.interactionState=[NFBStateLedger new];
    CFTimeInterval now=CACurrentMediaTime();
    // Keep the fast touch repair on known paths; discover newly visible pages at
    // most every 0.25 seconds, independent of the manager's multiple callers.
    if (!self.knownInteractiveViews || now-self.lastInteractionScan>=0.25) {
        self.lastInteractionScan=now;
        self.knownInteractiveViews=[NSHashTable weakObjectsHashTable];
        NSMutableArray<UIView *> *stack=[NSMutableArray arrayWithObject:self.desktop];
        while (stack.count) {
            UIView *view=stack.lastObject; [stack removeLastObject];
            if (view.hidden || view.alpha<0.01) continue;
            [stack addObjectsFromArray:view.subviews];
            if ([view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UIControl.class] ||
                [NSStringFromClass(view.class) containsString:@"IconView"] || view.gestureRecognizers.count)
                [self.knownInteractiveViews addObject:view];
        }
    }
    for (UIView *view in self.knownInteractiveViews.allObjects) {
        if (![view isDescendantOfView:self.desktop] || view.hidden || view.alpha<0.01) continue;
        BOOL visible=YES;
        for (UIView *ancestor=view; ancestor && ancestor!=self.canvas; ancestor=ancestor.superview)
            if (ancestor.hidden || ancestor.alpha<0.01) { visible=NO; break; }
        if (!visible) continue;
        for (UIView *ancestor=view; ancestor && ancestor!=self.canvas; ancestor=ancestor.superview) {
            if (!ancestor.userInteractionEnabled) {
                [self.interactionState remember:ancestor key:@"interaction" restore:^{ ancestor.userInteractionEnabled=NO; }];
                ancestor.userInteractionEnabled=YES;
            }
        }
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll=(UIScrollView *)view; BOOL enabled=scroll.scrollEnabled;
            [self.interactionState remember:scroll key:@"scroll" restore:^{ scroll.scrollEnabled=enabled; }];
            if (!enabled) scroll.scrollEnabled=YES;
        }
        for (UIGestureRecognizer *gesture in view.gestureRecognizers)
            if (!gesture.enabled && ([gesture isKindOfClass:UITapGestureRecognizer.class] ||
                ([view isKindOfClass:UIScrollView.class] && gesture==[(UIScrollView *)view panGestureRecognizer]))) {
                [self.interactionState remember:gesture key:@"gesture" restore:^{ gesture.enabled=NO; }];
                gesture.enabled=YES;
            }
    }
}
- (void)restoreDesktopInteraction {
    [self.interactionState restore]; self.interactionState=nil; self.knownInteractiveViews=nil;
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
    // The wallpaper and native desktop fill the whole pane.
    if (!CGRectEqualToRect(self.canvas.frame,self.panel.bounds)) self.canvas.frame = self.panel.bounds;
    double scale = NFBDesktopScale(CGRectGetWidth(self.originalBounds), CGRectGetHeight(self.originalBounds),
        CGRectGetWidth(self.canvas.bounds),CGRectGetHeight(self.canvas.bounds));
    if (!(scale > 0)) return NFBDesktopFail(@"桌面尺寸无效");
    // Keep SpringBoard's desktop in native coordinates. Only this outer host
    // owns the pane transform; folder transitions may animate desktop geometry.
    UIView *host = self.desktopHost;
    CGPoint center = CGPointMake(CGRectGetMidX(self.canvas.bounds),CGRectGetMidY(self.canvas.bounds));
    CGAffineTransform transform = CGAffineTransformMakeScale(scale,scale);
    if (!CGRectEqualToRect(host.bounds,self.originalBounds)) host.bounds = self.originalBounds;
    if (!CGPointEqualToPoint(host.center,center)) host.center = center;
    if (!CGAffineTransformEqualToTransform(host.transform,transform)) host.transform = transform;
    return YES;
}
- (void)check {
    if (session != self || self.restoring) return;
    // 10 Hz timer. Every other private-API path in this file is wrapped; this one
    // was not, so a single throw here terminated SpringBoard.
    @try { [self checkBody]; }
    @catch (NSException *error) {
        NFBErrorLog(@"desktop split check failed: %@", error);
        failurePending = YES; NFBCloseDesktopSplit();
    }
}
- (void)checkBody {
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
    if (self.desktop.superview != self.desktopHost || ![self place]) {
        if (self.desktop.superview != self.desktopHost) NFBDesktopFail(@"系统重新调整了桌面视图，已恢复桌面");
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
    self.restoring=YES;
    [self.timer invalidate]; self.timer=nil;
    [self finishWidgetRefresh];
    [self restoreDesktopInteraction];
    if (self.suppliedAppearance) {
        NFBAttemptCleanup(@"desktop lifecycle", ^{
            [self.desktopController beginAppearanceTransition:NO animated:NO];
            [self.desktopController endAppearanceTransition];
        });
        self.suppliedAppearance=NO;
    }
    [self restoreDesktopAppearance];
    UIView *view=self.desktop;
    if (self.mutated && view && self.originalParent) {
        NFBAttemptCleanup(@"desktop geometry", ^{
            view.transform=CGAffineTransformIdentity;
            view.bounds=self.originalBounds; view.center=self.originalCenter;
            view.autoresizingMask=self.originalAutoresizing;
            view.translatesAutoresizingMaskIntoConstraints=self.originalTranslates;
            view.hidden=self.originalHidden; view.alpha=self.originalAlpha;
            view.userInteractionEnabled=self.originalInteraction;
        });
        NFBAttemptCleanup(@"desktop parent", ^{
            [self.originalParent insertSubview:view atIndex:MIN(self.originalIndex,self.originalParent.subviews.count)];
            view.transform=self.originalTransform;
        });
        NFBAttemptCleanup(@"desktop constraints", ^{ [NSLayoutConstraint activateConstraints:self.constraints]; });
        NFBAttemptCleanup(@"desktop layout", ^{ [self.originalParent setNeedsLayout]; [self.originalParent layoutIfNeeded]; });
        // A failing private parent must not leave the desktop owned by a retiring panel.
        if ([view isDescendantOfView:self.panel])
            NFBAttemptCleanup(@"desktop fallback parent", ^{ [self.window addSubview:view]; });
    }
    NFBAttemptCleanup(@"panel", ^{ [self.panel removeFromSuperview]; });
    NFBAttemptCleanup(@"backdrop", ^{ [self.backgroundFrost removeFromSuperview]; });
    [self.siblingState restore]; self.siblingState=nil;
    if (self.windowMutated) {
        NFBAttemptCleanup(@"window color", ^{ self.window.backgroundColor=self.originalWindowColor; self.window.opaque=self.originalWindowOpaque; });
        NFBAttemptCleanup(@"window level", ^{ self.window.windowLevel=self.originalWindowLevel; });
        NFBAttemptCleanup(@"window alpha", ^{ self.window.alpha=self.originalWindowAlpha; });
        NFBAttemptCleanup(@"window interaction", ^{ self.window.userInteractionEnabled=self.originalWindowInteraction; });
        NFBAttemptCleanup(@"window visibility", ^{ self.window.hidden=self.originalWindowHidden; });
        NFBAttemptCleanup(@"window focus", ^{
            if (self.window.isKeyWindow && self.previousKeyWindow && !self.previousKeyWindow.hidden)
                [self.previousKeyWindow makeKeyWindow];
        });
    }
    self.backgroundFrost=nil; self.window=nil; self.desktop=nil; self.originalParent=nil;
    self.constraints=nil; self.desktopController=nil;
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
        UIView *desktop = NFBDesktopSource(anchor);
        if (!desktop) return NFBDesktopFail(@"没有找到已加载的系统桌面视图");
        NFBWindowState *state = NFBCurrentWindowState();
        next.startedHome = state.home;
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
        NFBInstallDesktopFolderAnimationHook();
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
        // Start hidden when the open animation is enabled, otherwise the fully
        // assembled pane is visible for a frame before the scale-in begins.
        BOOL animateOpen = NFBDesktopAnimationsEnabled();
        if (animateOpen) { panel.alpha = 0; panel.transform = CGAffineTransformMakeScale(0.94,0.94); }
        next.panel = panel; [window addSubview:panel];
        // Clear so the wallpaper - from the desktop subtree or borrowed below -
        // shows through instead of a flat system background.
        UIView *canvas = [UIView new]; canvas.backgroundColor = UIColor.clearColor;
        canvas.clipsToBounds = YES; next.canvas = canvas; [panel addSubview:canvas];
        UIView *desktopHost = [UIView new]; desktopHost.backgroundColor = UIColor.clearColor;
        next.desktopHost = desktopHost; [canvas addSubview:desktopHost];
        // Verify geometry before touching the desktop hierarchy.
        if (![next place]) { [next restore]; return NO; }
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
        [desktopHost addSubview:desktop];
        // Establish native geometry once. The periodic check must not overwrite
        // positions or transforms that SpringBoard owns during folder animation.
        desktop.transform = CGAffineTransformIdentity;
        desktop.bounds = next.originalBounds;
        desktop.center = CGPointMake(CGRectGetMidX(next.originalBounds),CGRectGetMidY(next.originalBounds));
        desktop.hidden = NO; desktop.alpha = 1; desktop.userInteractionEnabled = YES;
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
        next.siblingState=[NFBStateLedger new];
        for (UIView *sibling in window.subviews) {
            if (sibling==panel) continue;
            BOOL hidden=sibling.hidden;
            [next.siblingState remember:sibling key:@"sibling visibility" restore:^{ sibling.hidden=hidden; }];
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
                    @try {
                        [active.desktop setNeedsLayout]; [active.desktop layoutIfNeeded];
                        [active refreshWidgetPage];
                        NFBDebugLog(@"desktop widget appearance refreshed for fullscreen background");
                    } @catch (NSException *error) { NFBErrorLog(@"desktop widget activation failed: %@",error); }
                }
            });
        }
        next.timer = [NSTimer timerWithTimeInterval:0.1 target:next selector:@selector(check) userInfo:nil repeats:YES];
        // Keep the 100 ms safety/launch checks; let the run loop coalesce
        // wakeups by up to 10 ms without increasing polling frequency.
        next.timer.tolerance = 0.01;
        [NSRunLoop.mainRunLoop addTimer:next.timer forMode:NSRunLoopCommonModes];
        // effect must be committed before the animation: it is not animatable, and
        // assigning it inside the block made the blur appear in one frame.
        next.backgroundFrost.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        if (animateOpen) {
            [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                panel.alpha = 1; panel.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
        NFBDebugLog(@"desktop native host: view=%@ window=%@ root=%@ sameScene=%d pane=%@",
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
