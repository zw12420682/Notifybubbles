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
@implementation NFBDesktopSession
- (BOOL)place {
    UIWindow *window = self.window;
    CGRect screen = window.bounds;
    if (CGRectGetWidth(screen) >= CGRectGetHeight(screen)) return NFBDesktopFail(@"桌面分屏目前仅支持竖屏");
    UIEdgeInsets safe = window.safeAreaInsets;
    CGRect usable = UIEdgeInsetsInsetRect(screen, UIEdgeInsetsMake(MAX(12,safe.top),12,MAX(12,safe.bottom),12));
    if (!self.placed) {
        UIView *anchor = self.anchor;
        if (!anchor.window) return NFBDesktopFail(@"原分屏窗口已关闭");
        CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:anchor.window];
        anchorFrame = [window convertRect:anchorFrame fromWindow:anchor.window];
        CGFloat width = MIN(260, CGRectGetWidth(usable)*0.46);
        CGFloat height = MIN(CGRectGetHeight(usable)*0.78,
            width*CGRectGetHeight(self.originalBounds)/CGRectGetWidth(self.originalBounds)+36);
        if (width < 120 || height < 180) return NFBDesktopFail(@"屏幕可用空间不足");
        CGFloat x = CGRectGetMidX(anchorFrame) >= CGRectGetMidX(screen) ? CGRectGetMinX(usable) : CGRectGetMaxX(usable)-width;
        self.panelFrame = CGRectMake(x, CGRectGetMidY(usable)-height/2, width, height);
        self.placed = YES;
    }
    CGRect frame = self.panelFrame;
    frame.origin.x = MAX(CGRectGetMinX(usable), MIN(frame.origin.x, CGRectGetMaxX(usable)-frame.size.width));
    frame.origin.y = MAX(CGRectGetMinY(usable), MIN(frame.origin.y, CGRectGetMaxY(usable)-frame.size.height));
    self.panelFrame = frame;
    CGRect panelBounds = CGRectMake(0,0,frame.size.width,frame.size.height);
    CGPoint panelCenter = CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    if (!CGRectEqualToRect(self.panel.bounds,panelBounds)) self.panel.bounds = panelBounds;
    if (!CGPointEqualToPoint(self.panel.center,panelCenter)) self.panel.center = panelCenter;
    self.canvas.frame = CGRectMake(0,36,frame.size.width,frame.size.height-36);
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
    if (snapshot) [self.window.rootViewController.view addSubview:snapshot];
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
        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = UIColor.clearColor;
        window.rootViewController = controller;
        UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
        panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
        panel.layer.cornerRadius = 14; panel.clipsToBounds = YES;
        next.panel = panel; [controller.view addSubview:panel];
        UIView *canvas = [UIView new]; canvas.backgroundColor = UIColor.systemBackgroundColor;
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
        NFBDesktopFail([NSString stringWithFormat:@"桌面承载异常：%@", exception.name]);
        if (session == next) session = nil;
        [next restore];
        return NO;
    }
}
