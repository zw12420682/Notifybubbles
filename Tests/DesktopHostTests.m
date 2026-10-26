#import "NFBRailScrolling.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "NFBDesktopHost.h"
#import "NFBWindowState.h"

// Simulator fixtures supply the private classes; the host itself is production code.
@interface SBFolderContainerView : UIView @end
@implementation SBFolderContainerView @end
extern BOOL NFBDesktopSuppressFolderTracking(CALayer *, NSString *);
@interface SBRootFolderView : UIView @end
@implementation SBRootFolderView @end
@interface SBHomeScreenViewController : UIViewController
@property(nonatomic) NSUInteger appearances, disappearances;
@end
@implementation SBHomeScreenViewController
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; self.appearances++; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; self.disappearances++; }
@end
@interface DesktopAppIconFixture : UIView
@property(nonatomic,copy) NSString *applicationBundleIdentifier;
@end
@implementation DesktopAppIconFixture @end
@interface DesktopFolderIconFixture : NSObject @end
@implementation DesktopFolderIconFixture
- (BOOL)isFolderIcon { return YES; }
@end
@interface SBFolderIcon : NSObject @end
@implementation SBFolderIcon @end
@interface DesktopIconModelFixture : UIView
@property(nonatomic,strong) id icon;
@end
@implementation DesktopIconModelFixture @end
@interface DesktopFolderViewFixture : UIView @end
@implementation DesktopFolderViewFixture
- (BOOL)isFolderIcon { return YES; }
@end
@interface DesktopPagerFixture : UIScrollView
@property(nonatomic) NSUInteger moves;
@end
@implementation DesktopPagerFixture
- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    if (!CGPointEqualToPoint(offset,self.contentOffset)) self.moves++;
    [super setContentOffset:offset animated:animated];
}
@end
@interface DesktopRootFixture : UIView
@property(nonatomic) BOOL throwNextLayout;
@end
@implementation DesktopRootFixture
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.throwNextLayout) {
        self.throwNextLayout=NO;
        [NSException raise:@"FixtureLayoutFailure" format:@"Expected private layout failure"]; }
}
@end
extern BOOL NFBLaunchAppFromDesktopIcon(id);
static BOOL openAccepted=YES;
static NSString *submittedBundle;
BOOL NFBOpenTrollApp(NSString *bundle) { submittedBundle=bundle; return openAccepted; }
// The simulator has no TrollOpen; NFBDesktopHost asks for the floating-window
// class, so answer nil here instead of linking the real adapter.
Class NFBTrollFloatingWindowClass(void) { return Nil; }
BOOL NFBSplitTrollFrontmostApp(void) { submittedBundle=@"frontmost"; return openAccepted; }
// Reproduce the device log: the private wrapper stops hit testing at itself.
@interface _SBRootFolderLayoutWrapperView : UIView @end
@implementation _SBRootFolderLayoutWrapperView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha<0.01 || !self.userInteractionEnabled || ![self pointInside:point withEvent:event]) return nil;
    return self;
}
@end
@interface SBLockScreenManager : NSObject
@property(nonatomic) BOOL locked;
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end
@implementation SBLockScreenManager
+ (instancetype)sharedInstance { static id lock; if (!lock) lock=[self new]; return lock; }
- (BOOL)isUILocked { return self.locked; }
@end
@implementation NFBWindowState @end
static NFBWindowState *state;
NFBWindowState *NFBCurrentWindowState(void) { return state; }
void NFBInvalidateWindowState(void) {}
static void Check(BOOL valid, NSString *name) {
    if (!valid) [NSException raise:@"DesktopTestFailure" format:@"%@",name];
}
// A failed open is silent otherwise: carry the production reason plus the state
// that was rejected, so CI reports why instead of only which assertion tripped.
static NSString *NFBWindowSummary(void) {
    NSMutableArray *parts = [NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        [parts addObject:[NSString stringWithFormat:@"%@(hidden=%d,level=%.0f,root=%@)",
            NSStringFromClass(window.class), window.hidden, window.windowLevel,
            window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"nil"]];
#pragma clang diagnostic pop
    return [parts componentsJoinedByString:@", "];
}
static void CheckOpen(BOOL opened, NSString *name, UIView *desktop, UIView *root) {
    if (opened) return;
    NSString *detail = [NSString stringWithFormat:
        @"reason=%@ desktop.superview=%@ inRoot=%d bounds=%@ hidden=%d alpha=%.2f rootSubviews=%lu windows=[%@]",
        NFBDesktopSplitError(),
        desktop.superview ? NSStringFromClass(desktop.superview.class) : @"nil",
        desktop.superview == root, NSStringFromCGRect(desktop.bounds), desktop.hidden, desktop.alpha,
        (unsigned long)root.subviews.count, NFBWindowSummary()];
    [NSException raise:@"DesktopTestFailure" format:@"%@ | %@", name, detail];
}
static NSString *NFBHitPath(UIView *view, UIWindow *window, CGPoint point) {
    NSMutableArray *parts=[NSMutableArray array];
    for (UIView *current=view; current; current=current.superview) {
        CGPoint local=[current convertPoint:point fromView:window];
        [parts addObject:[NSString stringWithFormat:@"%@ frame=%@ bounds=%@ point=%@ inside=%d hidden=%d alpha=%.3f interaction=%d",
            NSStringFromClass(current.class),NSStringFromCGRect(current.frame),NSStringFromCGRect(current.bounds),
            NSStringFromCGPoint(local),[current pointInside:local withEvent:nil],current.hidden,(double)current.alpha,current.userInteractionEnabled]];
    }
    return [parts componentsJoinedByString:@" -> "];
}
extern UIView *NFBDesktopSplitHitTest(UIWindow *, CGPoint, UIEvent *, BOOL *);
@interface DesktopNativeWindowFixture : UIWindow
@end
@implementation DesktopNativeWindowFixture
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL handled=NO;
    UIView *hit=NFBDesktopSplitHitTest(self,point,event,&handled);
    return handled ? hit : [super hitTest:point withEvent:event];
}
@end
@interface TestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIWindow *appWindow;
@end
@implementation TestDelegate
- (BOOL)application:(__unused UIApplication *)application didFinishLaunchingWithOptions:(__unused NSDictionary *)options {
    self.window=[[DesktopNativeWindowFixture alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root=[UIViewController new];
    root.view=[[DesktopRootFixture alloc] initWithFrame:self.window.bounds];
    self.window.rootViewController=root;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ [self runTests]; });
    return YES;
}
- (void)runTests {
    [UIView setAnimationsEnabled:NO];
    NSString *result=@"PASS";
    @try {
        UIScrollView *railFixture=[[UIScrollView alloc] initWithFrame:CGRectMake(0,0,62,120)];
        railFixture.contentSize=CGSizeMake(62,300);
        CABasicAnimation *oldScroll=[CABasicAnimation animationWithKeyPath:@"bounds"];
        oldScroll.duration=2; [railFixture.layer addAnimation:oldScroll forKey:@"bounds"];
        CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.duration=2; [railFixture.layer addAnimation:fade forKey:@"opacity"];
        Check(NFBSettleRailOffset(railFixture,180),@"automatic rail reveal settles immediately");
        Check(railFixture.contentOffset.y==180 && ![railFixture.layer animationForKey:@"bounds"],@"obsolete scroll animation cannot override active reveal");
        Check([railFixture.layer animationForKey:@"opacity"]!=nil,@"rail reveal preserves unrelated animation");
        [railFixture.layer removeAllAnimations];
        state=[NFBWindowState new]; state.home=YES;
        UIViewController *root=self.window.rootViewController;
        SBHomeScreenViewController *home=[SBHomeScreenViewController new];
        [root addChildViewController:home];
        home.view=[[SBRootFolderView alloc] initWithFrame:root.view.bounds];
        [root.view addSubview:home.view]; [home didMoveToParentViewController:root];
        UIView *desktop=home.view; desktop.translatesAutoresizingMaskIntoConstraints=NO;
        NSArray *constraints=@[[desktop.leadingAnchor constraintEqualToAnchor:root.view.leadingAnchor],
            [desktop.topAnchor constraintEqualToAnchor:root.view.topAnchor],
            [desktop.widthAnchor constraintEqualToAnchor:root.view.widthAnchor],
            [desktop.heightAnchor constraintEqualToAnchor:root.view.heightAnchor]];
        [NSLayoutConstraint activateConstraints:constraints]; [root.view layoutIfNeeded];
        UIView *anchor=[[UIView alloc] initWithFrame:CGRectMake(30,200,180,380)];
        self.appWindow=[[UIWindow alloc] initWithFrame:self.window.frame];
        self.appWindow.rootViewController=[UIViewController new];
        self.appWindow.windowLevel=UIWindowLevelNormal+10;
        [self.appWindow.rootViewController.view addSubview:anchor];
        [self.appWindow makeKeyAndVisible]; state.floatingWindow=anchor;
        NSUInteger index=[root.view.subviews indexOfObjectIdenticalTo:desktop];
        UIWindow *nativeWindow=desktop.window;
        UIViewController *nativeRoot=nativeWindow.rootViewController;
        CGFloat nativeLevel=nativeWindow.windowLevel;
        CGRect originalAnchor=anchor.frame; NSUInteger originalSubviews=nativeWindow.subviews.count;
        anchor.frame=CGRectMake(30,200,50,80);
        Check(!NFBShowDesktopInSplit(anchor),@"invalid pane preflight fails");
        Check(nativeWindow.subviews.count==originalSubviews && desktop.superview==root.view,
            @"failed preflight leaves no panel attached to native window");
        anchor.frame=originalAnchor;
        CGRect bounds=desktop.bounds; CGPoint center=desktop.center;
        desktop.userInteractionEnabled=NO;
        UIView *wrapper=[[_SBRootFolderLayoutWrapperView alloc] initWithFrame:desktop.bounds];
        [desktop addSubview:wrapper];
        UIView *disabledContainer=[[UIView alloc] initWithFrame:desktop.bounds];
        disabledContainer.userInteractionEnabled=NO; [wrapper addSubview:disabledContainer];
        UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:disabledContainer.bounds];
        scroll.scrollEnabled=NO; scroll.userInteractionEnabled=NO; [disabledContainer addSubview:scroll];
        UIControl *touch=[[UIControl alloc] initWithFrame:CGRectMake(100,100,60,60)]; [scroll addSubview:touch];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] init]; tap.enabled=NO; [touch addGestureRecognizer:tap];
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open",desktop,root.view);
        Check(NFBDesktopSplitActive() && desktop.superview!=root.view,@"real view transferred");
        Check(desktop.window==nativeWindow && nativeWindow.rootViewController==nativeRoot,
            @"desktop remains in its native window and controller scene");
        SBFolderContainerView *folderContainer=[[SBFolderContainerView alloc] initWithFrame:desktop.bounds];
        [desktop addSubview:folderContainer];
        NSString *trackingKey=@"SBFolderSourceViewTrackingMatchMoveAnimation";
        Check(NFBDesktopSuppressFolderTracking(folderContainer.layer,trackingKey),@"bypass misplaced folder source tracking only in hosted desktop");
        for (NSString *key in @[@"transform",@"transform.scale.x",@"opacity",@"position",@"SBHLibraryPodIconZoomMatchMoveAnimation"])
            Check(!NFBDesktopSuppressFolderTracking(folderContainer.layer,key),@"preserve other native folder animations");
        Check(!NFBDesktopSuppressFolderTracking(desktop.layer,trackingKey),@"do not filter unrelated desktop layers");
        [folderContainer removeFromSuperview]; [root.view addSubview:folderContainer];
        Check(!NFBDesktopSuppressFolderTracking(folderContainer.layer,trackingKey),@"do not filter folder containers outside hosted desktop");
        // This full-size fixture is only for layer-filter scope checks. Detach
        // it before hit-testing so it cannot intercept the native child touch.
        [folderContainer removeFromSuperview];
        UIView *host=desktop.superview;
        UIView *panel=host.superview.superview;
        Check(CGRectEqualToRect(desktop.bounds,bounds) &&
            CGPointEqualToPoint(desktop.center,CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds))) &&
            CGAffineTransformIsIdentity(desktop.transform),@"desktop retains native coordinates inside scaled host");
        CGPoint nativeCenter=desktop.center;
        CGAffineTransform nativeTransform=desktop.transform;
        desktop.center=CGPointMake(nativeCenter.x+12,nativeCenter.y);
        desktop.transform=CGAffineTransformMakeScale(0.98,0.98);
        NFBUpdateDesktopSplit(YES);
        Check(CGPointEqualToPoint(desktop.center,CGPointMake(nativeCenter.x+12,nativeCenter.y)) &&
            CGAffineTransformEqualToTransform(desktop.transform,CGAffineTransformMakeScale(0.98,0.98)),
            @"periodic placement preserves native folder animation geometry");
        desktop.center=nativeCenter; desktop.transform=nativeTransform;
        CGRect paneRect=[panel convertRect:panel.bounds toView:desktop.window];
        paneRect=[self.window convertRect:paneRect fromWindow:desktop.window];
        Check(CGRectEqualToRect(paneRect,anchor.frame),@"split desktop pane matches the split app pane");
        BOOL hasFrost=NO;
        for (UIView *v in root.view.subviews) if ([v isKindOfClass:UIVisualEffectView.class]) hasFrost=YES;
        Check(hasFrost,@"desktop background is frosted");
        Check(desktop.userInteractionEnabled && desktop.translatesAutoresizingMaskIntoConstraints,@"native touches enabled");
        Check(disabledContainer.userInteractionEnabled && scroll.userInteractionEnabled && scroll.scrollEnabled && tap.enabled,
            @"nested disabled native touch paths restored in pane");
        disabledContainer.userInteractionEnabled=NO; scroll.scrollEnabled=NO; tap.enabled=NO;
        NFBUpdateDesktopSplit(YES);
        Check(disabledContainer.userInteractionEnabled && scroll.scrollEnabled && tap.enabled,
            @"later native interaction disabling is repaired");
        NFBUpdateDesktopSplit(YES);
        Check(self.window.isKeyWindow,@"native desktop receives focus at open");
        for (NSLayoutConstraint *constraint in constraints) Check(!constraint.active,@"external constraints detached");
        CGPoint point=[touch convertPoint:CGPointMake(30,30) toView:desktop.window];
        Check(folderContainer.superview==nil,@"touch-fixture-v2: folder test container detached before hit test");
        UIView *actualHit=[desktop.window hitTest:point withEvent:nil];
        Check(actualHit==touch,[NSString stringWithFormat:@"touch-fixture-v2: scaled hit testing reaches native child | point=%@ actual=[%@] expected=[%@] desktopChildren=%@",
            NSStringFromCGPoint(point),NFBHitPath(actualHit,desktop.window,point),NFBHitPath(touch,desktop.window,point),
            [desktop.subviews valueForKey:@"description"]]);
        UIView *hiddenPage=[[UIView alloc] initWithFrame:wrapper.bounds];
        hiddenPage.hidden=YES; [wrapper addSubview:hiddenPage];
        Check([desktop.window hitTest:point withEvent:nil]==touch,@"wrapper repair excludes hidden pages");
        [hiddenPage removeFromSuperview];
        UIView *emptyWrapper=[[_SBRootFolderLayoutWrapperView alloc] initWithFrame:desktop.bounds];
        [desktop addSubview:emptyWrapper];
        // Content is a sibling behind the empty layout overlay, as on the device.
        [desktop insertSubview:disabledContainer belowSubview:emptyWrapper];
        Check([desktop.window hitTest:point withEvent:nil]==touch,@"empty layout overlay routes to native content behind it");
        [emptyWrapper removeFromSuperview];
        [wrapper addSubview:disabledContainer];
        Check([desktop.window hitTest:CGPointMake(1,1) withEvent:nil]==nil,@"outside panel passes through");
        Check(desktop.window.isKeyWindow,@"touch activation gives native desktop focus");
        // Reattach only after all touch checks to verify session teardown also
        // stops filtering a folder that remains inside the native desktop.
        [desktop addSubview:folderContainer];
        Check(NFBDesktopSuppressFolderTracking(folderContainer.layer,trackingKey),@"tracking filter active immediately before session teardown");
        NFBCloseDesktopSplit(); NFBCloseDesktopSplit();
        Check(!NFBDesktopSuppressFolderTracking(folderContainer.layer,trackingKey),@"ordinary home screen tracking resumes after session closes");
        [folderContainer removeFromSuperview];
        Check(self.appWindow.isKeyWindow,@"desktop close restores previous app key window");
        Check(nativeWindow.rootViewController==nativeRoot && !nativeWindow.hidden && nativeWindow.windowLevel==nativeLevel,
            @"close preserves native root controller visibility and window level");
        wrapper.userInteractionEnabled=YES;
        Check([wrapper hitTest:CGPointMake(130,130) withEvent:nil]==wrapper,
            @"wrapper private behavior remains unchanged outside split session");
        for (UIView *v in root.view.subviews) Check(![v isKindOfClass:UIVisualEffectView.class],@"disabled animations clean backdrop synchronously");
        Check(!NFBDesktopSplitActive() && desktop.superview==root.view,@"idempotent restore");
        Check(!disabledContainer.userInteractionEnabled && !scroll.userInteractionEnabled && !scroll.scrollEnabled && !tap.enabled,
            @"nested touch and scroll state restored after close");
        Check([root.view.subviews indexOfObjectIdenticalTo:desktop]==index,@"original order");
        Check(CGRectEqualToRect(desktop.bounds,bounds) && CGPointEqualToPoint(desktop.center,center),@"original geometry");
        Check(CGAffineTransformIsIdentity(desktop.transform) && !desktop.userInteractionEnabled &&
            !desktop.translatesAutoresizingMaskIntoConstraints,@"original flags");
        for (NSLayoutConstraint *constraint in constraints) Check(constraint.active,@"constraints restored");
        CheckOpen(NFBShowDesktopInSplit(anchor),@"reopen",desktop,root.view);
        [SBLockScreenManager sharedInstance].locked=YES; NFBUpdateDesktopSplit(YES);
        Check(!NFBDesktopSplitActive() && desktop.superview==root.view,@"lock restores desktop");
        [SBLockScreenManager sharedInstance].locked=NO;
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open before app launch",desktop,root.view);
        state.home=NO; state.frontApp=@"com.example.new-app"; NFBUpdateDesktopSplit(YES);
        Check(NFBDesktopSplitActive(),@"desktop pane is independent of reported background scene");
        NFBCloseDesktopSplit();
        Check(desktop.superview==root.view,@"close before app launch restores native view"); state.home=YES; state.frontApp=nil;
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open for split icon launch",desktop,root.view);
        NSString *previousSubmission=submittedBundle;
        DesktopFolderViewFixture *folderView=[DesktopFolderViewFixture new]; [desktop addSubview:folderView];
        Check(!NFBLaunchAppFromDesktopIcon(folderView) && NFBDesktopSplitActive(),@"folder-view flag preserves native folder handling");
        DesktopIconModelFixture *modelView=[DesktopIconModelFixture new]; [desktop addSubview:modelView];
        modelView.icon=[DesktopFolderIconFixture new];
        Check(!NFBLaunchAppFromDesktopIcon(modelView),@"folder-model flag preserves native folder handling");
        modelView.icon=[SBFolderIcon new];
        Check(!NFBLaunchAppFromDesktopIcon(modelView),@"native folder class is accepted without flag getter");
        Check(submittedBundle==previousSubmission,@"opening folders never submits an app request");
        DesktopAppIconFixture *appIcon=[DesktopAppIconFixture new];
        appIcon.applicationBundleIdentifier=@"com.example.desktop-app"; [desktop addSubview:appIcon];
        openAccepted=NO;
        Check(NFBLaunchAppFromDesktopIcon(appIcon) && NFBDesktopSplitActive(),@"rejected split launch retains desktop");
        state.home=NO; state.frontApp=appIcon.applicationBundleIdentifier;
        Check(NFBLaunchAppFromDesktopIcon(appIcon) && [submittedBundle isEqualToString:@"frontmost"],
            @"launch resolves current foreground rather than captured opening state");
        state.home=YES; state.frontApp=nil;
        openAccepted=YES;
        Check(NFBLaunchAppFromDesktopIcon(appIcon) && [submittedBundle isEqualToString:appIcon.applicationBundleIdentifier],@"desktop icon uses Open split adapter");
        Check(!NFBLaunchAppFromDesktopIcon(folderView) && NFBDesktopSplitActive(),@"pending app launch does not swallow folder actions");
        NFBUpdateDesktopSplit(YES);
        Check(NFBDesktopSplitActive(),@"submitted launch alone does not close desktop");
        state.floatingApp=appIcon.applicationBundleIdentifier; state.floatingWindow=anchor; state.mini=YES;
        NFBUpdateDesktopSplit(YES); Check(NFBDesktopSplitActive(),@"mini window does not confirm split launch");
        state.mini=NO; NFBUpdateDesktopSplit(YES);
        Check(!NFBDesktopSplitActive(),@"visible target split automatically closes desktop");
        state.floatingApp=nil; [appIcon removeFromSuperview]; [folderView removeFromSuperview]; [modelView removeFromSuperview];
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open before restore exception",desktop,root.view);
        ((DesktopRootFixture *)root.view).throwNextLayout=YES;
        [root.view setNeedsLayout]; NFBCloseDesktopSplit();
        Check(desktop.superview==root.view && nativeWindow.windowLevel==nativeLevel && !nativeWindow.hidden && self.appWindow.isKeyWindow,
            @"layout exception cannot skip native window and focus restoration");
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open before disabling",desktop,root.view);
        NFBUpdateDesktopSplit(NO); Check(!NFBDesktopSplitActive(),@"disabled closes");
        state.home=NO; state.frontApp=@"com.example.background"; desktop.hidden=YES; desktop.alpha=0;
        NSUInteger appearances=home.appearances, disappearances=home.disappearances;
        CheckOpen(NFBShowDesktopInSplit(anchor),@"fullscreen app can open hidden desktop",desktop,root.view);
        Check(home.appearances==appearances+1,@"fullscreen background supplies home appearance for widget hosts");
        Check(!desktop.hidden && desktop.alpha==1,@"hidden native desktop displayed in pane");
        for (UIView *v in root.view.subviews) Check(![v isKindOfClass:UIVisualEffectView.class],@"fullscreen app background not blurred");
        NFBUpdateDesktopSplit(YES); Check(NFBDesktopSplitActive(),@"fullscreen background does not dismiss pane");
        anchor.hidden=YES; NFBUpdateDesktopSplit(YES);
        Check(NFBDesktopSplitActive(),@"independent pane survives original app pane hiding");
        anchor.hidden=NO; NFBCloseDesktopSplit();
        Check(home.disappearances==disappearances+1,@"fullscreen appearance is balanced at close");
        Check(desktop.hidden && desktop.alpha==0,@"original hidden state restored");
        desktop.hidden=NO; desktop.alpha=1; state.home=YES; state.frontApp=nil;
        [anchor removeFromSuperview];
        Check(!NFBShowDesktopInSplit(anchor),@"missing original window rejected");
        Check(desktop.superview==root.view && CGAffineTransformIsIdentity(desktop.transform) &&
            CGRectEqualToRect(desktop.bounds,bounds),@"failed preflight does not mutate desktop");
        [self.appWindow.rootViewController.view addSubview:anchor];
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open before system view move",desktop,root.view);
        [root.view addSubview:desktop]; NFBUpdateDesktopSplit(YES);
        Check(!NFBDesktopSplitActive() && NFBConsumeDesktopSplitFailure().length>0,@"unexpected system move reports failure");
        [self runAnimatedTests:desktop anchor:anchor root:root.view];
        return;
    } @catch (NSException *exception) { result=[NSString stringWithFormat:@"FAIL: %@",exception]; }
    [self finishResult:result];
}
- (void)finishResult:(NSString *)result {
    NFBCloseDesktopSplit();
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/desktop-test-result.txt"];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"%@",result);
}
- (void)runAnimatedTests:(UIView *)desktop anchor:(UIView *)anchor root:(UIView *)root {
    // Return to UIApplication's main event loop between each phase. A nested
    // runUntilDate inside one main-dispatch block starves main-queue completions.
    [UIView setAnimationsEnabled:YES];
    @try { CheckOpen(NFBShowDesktopInSplit(anchor),@"animated desktop opening",desktop,root); }
    @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.4*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        @try {
            NFBCloseDesktopSplit();
            Check(desktop.superview==root,@"animated close restores native view immediately");
        } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.7*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
            @try {
                for (UIView *v in root.subviews) Check(![v isKindOfClass:UIVisualEffectView.class],@"animated close eventually removes backdrop");
                Check(desktop.superview==root,@"desktop home before reopening after animated close");
                CheckOpen(NFBShowDesktopInSplit(anchor),@"open before rapid fullscreen reopen",desktop,root);
                NFBCloseDesktopSplit();
                state.home=NO; state.frontApp=@"com.example.background";
                CheckOpen(NFBShowDesktopInSplit(anchor),@"rapid fullscreen reopen",desktop,root);
                for (UIView *v in root.subviews) Check(![v isKindOfClass:UIVisualEffectView.class],@"rapid reopen does not inherit retiring backdrop");
                NFBCloseDesktopSplit();
            } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.7*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
                @try {
                    for (UIView *v in root.subviews) Check(![v isKindOfClass:UIVisualEffectView.class],@"late old callback cannot leave a backdrop");
                    [self runWidgetRefreshTests:desktop anchor:anchor root:root];
                } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; }
            });
        });
    });
}
- (void)runWidgetRefreshTests:(UIView *)desktop anchor:(UIView *)anchor root:(UIView *)root {
    [UIView setAnimationsEnabled:NO];
    state.home=NO; state.frontApp=@"com.example.background";
    DesktopPagerFixture *pager=[[DesktopPagerFixture alloc] initWithFrame:desktop.bounds];
    pager.pagingEnabled=YES;
    pager.contentSize=CGSizeMake(pager.bounds.size.width*2,pager.bounds.size.height);
    CGPoint original=CGPointMake(pager.bounds.size.width,0);
    [pager setContentOffset:original animated:NO]; pager.moves=0;
    [desktop addSubview:pager];
    @try { CheckOpen(NFBShowDesktopInSplit(anchor),@"widget page refresh open",desktop,root); }
    @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
    [self awaitWidgetRefresh:pager original:original desktop:desktop anchor:anchor root:root deadline:CACurrentMediaTime()+3];
}
- (void)awaitWidgetRefresh:(DesktopPagerFixture *)pager original:(CGPoint)original desktop:(UIView *)desktop
                    anchor:(UIView *)anchor root:(UIView *)root deadline:(CFTimeInterval)deadline {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.05*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        BOOL complete=pager.moves>=2 && CGPointEqualToPoint(pager.contentOffset,original);
        if (!complete && CACurrentMediaTime()<deadline) {
            [self awaitWidgetRefresh:pager original:original desktop:desktop anchor:anchor root:root deadline:deadline];
            return;
        }
        @try {
            Check(complete,[NSString stringWithFormat:@"automatic page roundtrip restores exact original page: moves=%lu actual=%@ expected=%@ bounds=%@ content=%@ active=%d",
                (unsigned long)pager.moves,NSStringFromCGPoint(pager.contentOffset),NSStringFromCGPoint(original),
                NSStringFromCGRect(pager.bounds),NSStringFromCGSize(pager.contentSize),NFBDesktopSplitActive()]);
            NFBCloseDesktopSplit();
            Check(CGPointEqualToPoint(pager.contentOffset,original),@"closing preserves refreshed page position");
            [pager removeFromSuperview];
            [self runWidgetCancellationTests:desktop anchor:anchor root:root];
        } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; }
    });
}
- (void)runWidgetCancellationTests:(UIView *)desktop anchor:(UIView *)anchor root:(UIView *)root {
    DesktopPagerFixture *pager=[[DesktopPagerFixture alloc] initWithFrame:desktop.bounds];
    pager.pagingEnabled=YES;
    pager.contentSize=CGSizeMake(pager.bounds.size.width*2,pager.bounds.size.height);
    CGPoint original=CGPointMake(pager.bounds.size.width,0);
    [pager setContentOffset:original animated:NO]; [desktop addSubview:pager];
    @try { CheckOpen(NFBShowDesktopInSplit(anchor),@"refresh cancellation open",desktop,root); }
    @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.03*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        @try {
            NFBCloseDesktopSplit();
            Check(CGPointEqualToPoint(pager.contentOffset,original),@"close cancels in-flight refresh and restores page");
            [pager removeFromSuperview];
            CheckOpen(NFBShowDesktopInSplit(anchor),@"fresh session after canceled refresh",desktop,root);
        } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
            @try {
                Check(NFBDesktopSplitActive() && CGPointEqualToPoint(pager.contentOffset,original),@"old refresh callback cannot mutate replacement session");
                NFBCloseDesktopSplit();
                pager.contentSize=pager.bounds.size; [pager setContentOffset:CGPointZero animated:NO]; pager.moves=0;
                [desktop addSubview:pager];
                CheckOpen(NFBShowDesktopInSplit(anchor),@"single page open",desktop,root);
            } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
                @try {
                    Check(pager.moves==0 && CGPointEqualToPoint(pager.contentOffset,CGPointZero),@"single page never scrolls outside its content");
                    NFBCloseDesktopSplit(); [pager removeFromSuperview]; [self finishResult:@"PASS"];
                } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; }
            });
        });
    });
}

@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TestDelegate.class)); } }
