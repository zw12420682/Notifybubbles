#import <UIKit/UIKit.h>
#import "NFBDesktopHost.h"
#import "NFBWindowState.h"

// Simulator fixtures supply the private classes; the host itself is production code.
@interface SBRootFolderView : UIView @end
@implementation SBRootFolderView @end
@interface SBHomeScreenViewController : UIViewController @end
@implementation SBHomeScreenViewController @end
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
void NFBUpdateDesktopFreeze(__unused BOOL enabled, __unused CGFloat opacity) {}
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
@interface UIWindow (DesktopActivationFixture)
@property(nonatomic,copy) void (^activateDesktop)(void);
@end
@interface TestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation TestDelegate
- (BOOL)application:(__unused UIApplication *)application didFinishLaunchingWithOptions:(__unused NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root=[UIViewController new]; self.window.rootViewController=root;
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ [self runTests]; });
    return YES;
}
- (void)runTests {
    [UIView setAnimationsEnabled:NO];
    NSString *result=@"PASS";
    @try {
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
        [root.view addSubview:anchor]; state.floatingWindow=anchor;
        NSUInteger index=[root.view.subviews indexOfObjectIdenticalTo:desktop];
        CGRect bounds=desktop.bounds; CGPoint center=desktop.center;
        desktop.userInteractionEnabled=NO;
        UIView *disabledContainer=[[UIView alloc] initWithFrame:desktop.bounds];
        disabledContainer.userInteractionEnabled=NO; [desktop addSubview:disabledContainer];
        UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:disabledContainer.bounds];
        scroll.scrollEnabled=NO; scroll.userInteractionEnabled=NO; [disabledContainer addSubview:scroll];
        UIControl *touch=[[UIControl alloc] initWithFrame:CGRectMake(100,100,60,60)]; [scroll addSubview:touch];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] init]; tap.enabled=NO; [touch addGestureRecognizer:tap];
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open",desktop,root.view);
        Check(NFBDesktopSplitActive() && desktop.superview!=root.view,@"real view transferred");
        UIView *panel=desktop.superview.superview;
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
        Check(self.window.isKeyWindow,@"original focus preserved");
        for (NSLayoutConstraint *constraint in constraints) Check(!constraint.active,@"external constraints detached");
        CGPoint point=[touch convertPoint:CGPointMake(30,30) toView:desktop.window];
        Check([desktop.window hitTest:point withEvent:nil]==touch,@"scaled hit testing reaches native child");
        Check([desktop.window hitTest:CGPointMake(1,1) withEvent:nil]==nil,@"outside panel passes through");
        void (^activate)(void)=desktop.window.activateDesktop;
        Check(activate!=nil,@"desktop focus activation installed"); activate();
        Check(desktop.window.isKeyWindow,@"touch activation gives native desktop focus");
        NFBCloseDesktopSplit(); NFBCloseDesktopSplit();
        Check(self.window.isKeyWindow,@"desktop close restores previous key window");
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
        CheckOpen(NFBShowDesktopInSplit(anchor),@"open before disabling",desktop,root.view);
        NFBUpdateDesktopSplit(NO); Check(!NFBDesktopSplitActive(),@"disabled closes");
        state.home=NO; state.frontApp=@"com.example.background"; desktop.hidden=YES; desktop.alpha=0;
        CheckOpen(NFBShowDesktopInSplit(anchor),@"fullscreen app can open hidden desktop",desktop,root.view);
        Check(!desktop.hidden && desktop.alpha==1,@"hidden native desktop displayed in pane");
        for (UIView *v in root.view.subviews) Check(![v isKindOfClass:UIVisualEffectView.class],@"fullscreen app background not blurred");
        NFBUpdateDesktopSplit(YES); Check(NFBDesktopSplitActive(),@"fullscreen background does not dismiss pane");
        anchor.hidden=YES; NFBUpdateDesktopSplit(YES);
        Check(NFBDesktopSplitActive(),@"independent pane survives original app pane hiding");
        anchor.hidden=NO; NFBCloseDesktopSplit();
        Check(desktop.hidden && desktop.alpha==0,@"original hidden state restored");
        desktop.hidden=NO; desktop.alpha=1; state.home=YES; state.frontApp=nil;
        [anchor removeFromSuperview];
        Check(!NFBShowDesktopInSplit(anchor),@"missing original window rejected");
        Check(desktop.superview==root.view && CGAffineTransformIsIdentity(desktop.transform) &&
            CGRectEqualToRect(desktop.bounds,bounds),@"failed preflight does not mutate desktop");
        [root.view addSubview:anchor];
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
                    [self finishResult:@"PASS"];
                } @catch (NSException *e) { [self finishResult:[NSString stringWithFormat:@"FAIL: %@",e]]; }
            });
        });
    });
}

@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TestDelegate.class)); } }
