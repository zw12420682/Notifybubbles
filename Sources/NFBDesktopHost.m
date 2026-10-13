#import "NFBDesktopHost.h"
#import "NFBDesktopGeometry.h"
#import "NFBInterfaces.h"
#import "NFBWindowState.h"
#import "NFBDebugLog.h"
#import "NFBPrivacy.h"
#import <QuartzCore/QuartzCore.h>

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
@property(nonatomic, strong) id lockObserver;
@property(nonatomic) BOOL restoring, mutated;
- (BOOL)place;
- (void)closePressed;
- (void)check;
- (void)restore;
@end
static NFBDesktopSession *session;

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
    return [view isKindOfClass:UIView.class] && view.superview && view.window &&
        view != anchor && ![anchor isDescendantOfView:view] && ![view isDescendantOfView:anchor] &&
        NFBDesktopContainsRootFolder(view) && !NFBDesktopContainsFloating(view) &&
        CGRectGetWidth(view.bounds) > 0 && CGRectGetHeight(view.bounds) > 0 &&
        CGAffineTransformIsIdentity(view.transform) && !view.hidden && view.alpha > 0.01;
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
        if (window.hidden || window.alpha < 0.01) continue;
        UIView *view = NFBDesktopFromController(window.rootViewController, anchor);
        if (view) return view;
    }
    id icons = NFBCheckedObject(NSClassFromString(@"SBIconController"), @"sharedInstance");
    if ([icons isKindOfClass:UIViewController.class] && [(UIViewController *)icons isViewLoaded]) {
        UIView *view = [(UIViewController *)icons view];
        if (NFBDesktopEligible(view, anchor)) return view;
    }
    for (UIWindow *window in NFBDesktopWindows()) {
        if (window.hidden || window.alpha < 0.01) continue;
        UIView *view = NFBDesktopContentInTree(window, anchor);
        if (view) return view;
    }
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
    UIView *anchor = self.anchor;
    if (!anchor.window || anchor.hidden || anchor.alpha < 0.01 || CGRectIsEmpty(anchor.bounds)) return NO;
    for (UIView *parent = anchor.superview; parent; parent = parent.superview)
        if (parent.hidden || parent.alpha < 0.01) return NO;
    UIWindow *window = self.window;
    CGRect frame = [anchor convertRect:anchor.bounds toView:window];
    CGRect screen = window.bounds;
    if (!CGRectContainsRect(screen, frame) || frame.size.width < 120 || frame.size.height < 180 ||
        frame.size.width >= frame.size.height || CGRectGetWidth(screen) >= CGRectGetHeight(screen)) return NO;
    self.panel.frame = frame;
    self.canvas.frame = CGRectMake(0, 36, frame.size.width, frame.size.height - 36);
    double scale = NFBDesktopScale(CGRectGetWidth(self.originalBounds), CGRectGetHeight(self.originalBounds),
        CGRectGetWidth(self.canvas.bounds), CGRectGetHeight(self.canvas.bounds));
    if (!(scale > 0)) return NO;
    if (self.desktop.superview == self.canvas) {
        CGPoint center = CGPointMake(CGRectGetMidX(self.canvas.bounds), CGRectGetMidY(self.canvas.bounds));
        CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
        if (!CGRectEqualToRect(self.desktop.bounds, self.originalBounds)) self.desktop.bounds = self.originalBounds;
        if (!CGPointEqualToPoint(self.desktop.center, center)) self.desktop.center = center;
        if (!CGAffineTransformEqualToTransform(self.desktop.transform, transform)) self.desktop.transform = transform;
        self.desktop.hidden = NO; self.desktop.alpha = 1; self.desktop.userInteractionEnabled = YES;
    }
    // This window never becomes key, so keyboard and normal app focus stay native.
    window.windowLevel = anchor.window.windowLevel + 1;
    return YES;
}
- (void)closePressed { NFBCloseDesktopSplit(); }
- (void)check {
    if (session != self || self.restoring) return;
    NFBWindowState *state = NFBCurrentWindowState();
    if (!state.home || NFBDesktopLocked() || self.desktop.superview != self.canvas ||
        (state.floatingWindow && state.floatingWindow != self.anchor) || state.mini || !self.originalParent.window || ![self place]) NFBCloseDesktopSplit();
}
- (void)restore {
    if (self.restoring) return;
    self.restoring = YES;
    [self.timer invalidate]; self.timer = nil;
    if (self.lockObserver) [NSNotificationCenter.defaultCenter removeObserver:self.lockObserver];
    self.lockObserver = nil;
    self.window.hidden = YES;
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
    self.window.rootViewController = nil;
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
BOOL NFBShowDesktopInSplit(UIView *anchor) {
    if (!NSThread.isMainThread || !anchor.window || !NFBCurrentWindowState().home || NFBDesktopLocked()) return NO;
    if (session) { NFBCloseDesktopSplit(); return YES; }
    NFBDesktopSession *next = [NFBDesktopSession new];
    @try {
        NFBUpdateDesktopFreeze(NO, 0);
        UIView *desktop = NFBDesktopSource(anchor);
        if (!desktop) { NFBErrorLog(@"desktop host: complete native home view unavailable"); return NO; }
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
        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = UIColor.clearColor;
        window.rootViewController = controller;
        UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
        panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
        panel.layer.cornerRadius = 14; panel.clipsToBounds = YES;
        next.panel = panel; [controller.view addSubview:panel];
        UIView *canvas = [UIView new]; canvas.backgroundColor = UIColor.systemBackgroundColor;
        canvas.clipsToBounds = YES; next.canvas = canvas; [panel addSubview:canvas];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 150, 36)];
        label.text = @"系统桌面"; label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [panel addSubview:label];
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(0, 0, 36, 36); close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        close.accessibilityLabel = @"关闭桌面分屏并恢复桌面";
        [close addTarget:next action:@selector(closePressed) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:close];
        // Verify geometry before touching the desktop hierarchy.
        if (![next place]) { next.desktop = nil; return NO; }
        close.frame = CGRectMake(CGRectGetWidth(panel.bounds) - 36, 0, 36, 36);
        next.mutated = YES;
        [NSLayoutConstraint deactivateConstraints:next.constraints];
        desktop.translatesAutoresizingMaskIntoConstraints = YES; desktop.autoresizingMask = UIViewAutoresizingNone;
        [canvas addSubview:desktop];
        if (![next place]) { [next restore]; return NO; }
        session = next;
        window.hidden = NO;
        next.timer = [NSTimer timerWithTimeInterval:0.1 target:next selector:@selector(check) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:next.timer forMode:NSRunLoopCommonModes];
        next.lockObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { NFBCloseDesktopSplit(); }];
        NFBDebugLog(@"desktop host: native view %@ moved into split panel", NSStringFromClass(desktop.class));
        return YES;
    } @catch (NSException *exception) {
        NFBErrorLog(@"desktop host failed: %@", exception);
        if (session == next) session = nil;
        [next restore];
        return NO;
    }
}
