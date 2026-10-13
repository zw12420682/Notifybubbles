#import "NFBDesktopHost.h"
#import "NFBDesktopGeometry.h"
#import "NFBInterfaces.h"
#import "NFBWindowState.h"
#import "NFBSystemDesktop.h"
#import "NFBDebugLog.h"
#import "NFBPrivacy.h"
#import <QuartzCore/QuartzCore.h>
#ifndef NFB_DESKTOP_SIM_TEST
#import <substrate.h>
#endif
#include <math.h>

@interface NFBDesktopWindow : UIWindow
@end
@implementation NFBDesktopWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end

@interface NFBDesktopSession : NSObject
@property(nonatomic, strong) NFBDesktopWindow *window;
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
// Keep one retiring transition so rapid reopening cannot inherit its backdrop.
static UIWindow *retiringWindow;
static UIVisualEffectView *retiringFrost;
static BOOL NFBDesktopAnimationsEnabled(void) {
    return UIView.areAnimationsEnabled && !UIAccessibilityIsReduceMotionEnabled();
}
static void NFBFinishRetiringDesktop(void) {
    [retiringFrost.layer removeAllAnimations];
    [retiringFrost removeFromSuperview];
    retiringWindow.hidden = YES;
    retiringWindow.rootViewController = nil;
    retiringFrost = nil; retiringWindow = nil;
}
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
    if (content && [view isKindOfClass:content] && NFBDesktopEligible(view, anchor)) return view;
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
    self.paneBackdrop = backdrop;
    [self.canvas insertSubview:backdrop atIndex:0];
    NFBDebugLog(@"desktop pane: backdrop installed (%@)", NSStringFromClass(backdrop.class));
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
    if (self.desktop.superview != self.canvas || ![self place]) {
        if (self.desktop.superview != self.canvas) NFBDesktopFail(@"系统重新调整了桌面视图，已恢复桌面");
        failurePending = YES; NFBCloseDesktopSplit();
    }
}
- (void)restore {
    if (self.restoring) return;
    self.restoring = YES;
    [self.timer invalidate]; self.timer = nil;
    UIView *snapshot = NFBDesktopAnimationsEnabled() ? [self.panel snapshotViewAfterScreenUpdates:NO] : nil;
    snapshot.frame = self.panel.frame; snapshot.userInteractionEnabled = NO;
    if (snapshot) [self.window addSubview:snapshot];
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
    UIWindow *window = self.window;
    UIVisualEffectView *frost = self.backgroundFrost;
    NFBFinishRetiringDesktop();
    retiringWindow = window; retiringFrost = frost;
    void (^finish)(BOOL) = ^(__unused BOOL done) {
        [frost removeFromSuperview];
        window.hidden = YES; window.rootViewController = nil;
        if (retiringWindow == window) { retiringWindow = nil; retiringFrost = nil; }
    };
    if (NFBDesktopAnimationsEnabled()) {
        [UIView animateWithDuration:0.22 animations:^{
            snapshot.alpha = 0; snapshot.transform = CGAffineTransformMakeScale(0.94,0.94);
            frost.effect = nil; frost.alpha = 0;
        } completion:finish];
        // Completion can be delayed or interrupted; bound the lifetime of the
        // retiring overlay independently. This block only owns this transition.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.45*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
            finish(NO);
        });
    } else finish(YES);
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
    // Restore the native view before SpringBoard begins its app-launch transition.
    NFBCloseDesktopSplit();
    originalLaunchIcon(object,selector,icon,actions);
}
static void NFBInstallDesktopLaunchHook(void) {
    static BOOL installed;
    if (installed) return;
    Class cls = NSClassFromString(@"SBIconController");
    SEL selector = NSSelectorFromString(@"_launchFromIconView:withActions:");
    Method method = class_getInstanceMethod(cls,selector);
    if (!method) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 4 || strcmp(signature.methodReturnType,"v") ||
        [signature getArgumentTypeAtIndex:2][0] != '@' || [signature getArgumentTypeAtIndex:3][0] != '@') return;
    MSHookMessageEx(cls,selector,(IMP)NFBDesktopLaunchIcon,(IMP *)&originalLaunchIcon);
    installed = YES;
}
#endif
BOOL NFBShowDesktopInSplit(UIView *anchor) {
    if (!NSThread.isMainThread) return NO;
    lastFailure = nil; failurePending = NO;
    if (!anchor.window) return NFBDesktopFail(@"没有可用的分屏窗口");
    if (NFBDesktopLocked()) return NFBDesktopFail(@"锁屏时不能打开桌面分屏");
    if (session) { NFBCloseDesktopSplit(); return YES; }
    NFBFinishRetiringDesktop();
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
        NFBDesktopWindow *window;
        if (anchor.window.windowScene) window = [[NFBDesktopWindow alloc] initWithWindowScene:anchor.window.windowScene];
        else window = [[NFBDesktopWindow alloc] initWithFrame:anchor.window.screen.bounds];
        next.window = window;
        window.frame = anchor.window.screen.bounds;
        window.windowLevel = MAX(anchor.window.windowLevel+2, UIWindowLevelStatusBar+1);
        // Deliberately no root view controller: the panel is a direct subview of the
        // window. The transplanted desktop view belongs to the home screen controller,
        // and inserting it under a second, unrelated controller makes UIKit refuse the
        // insert with UIViewControllerHierarchyInconsistency.
        window.backgroundColor = UIColor.clearColor;
        UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
        panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
        panel.layer.cornerRadius = 14; panel.clipsToBounds = YES;
        next.panel = panel; [window addSubview:panel];
        // Clear so the wallpaper - from the desktop subtree or borrowed below -
        // shows through instead of a flat system background.
        UIView *canvas = [UIView new]; canvas.backgroundColor = UIColor.clearColor;
        canvas.clipsToBounds = YES; next.canvas = canvas; [panel addSubview:canvas];
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,0,36)];
        header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:next action:@selector(drag:)]];
        [panel addSubview:header];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 120, 36)];
        label.text = @"系统桌面"; label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [header addSubview:label];
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(0, 0, 36, 36); close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        close.accessibilityLabel = @"关闭桌面分屏并恢复桌面";
        [close addTarget:next action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:close];
        // Verify geometry before touching the desktop hierarchy.
        if (![next place]) { next.desktop = nil; return NO; }
        close.frame = CGRectMake(CGRectGetWidth(panel.bounds) - 36, 0, 36, 36);
        header.frame = CGRectMake(0,0,CGRectGetWidth(panel.bounds),36);
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
        if (next.wallpaperCount == 0) [next installPaneBackdrop];
#ifndef NFB_DESKTOP_SIM_TEST
        NFBInstallDesktopLaunchHook();
#endif
        session = next;
        window.hidden = NO;
        next.timer = [NSTimer timerWithTimeInterval:0.1 target:next selector:@selector(check) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:next.timer forMode:NSRunLoopCommonModes];
        if (NFBDesktopAnimationsEnabled()) {
            panel.alpha = 0; panel.transform = CGAffineTransformMakeScale(0.94,0.94);
            [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                panel.alpha = 1; panel.transform = CGAffineTransformIdentity;
                next.backgroundFrost.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
            } completion:nil];
        } else next.backgroundFrost.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        NFBDebugLog(@"desktop host: native view %@ moved into split panel", NSStringFromClass(desktop.class));
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
