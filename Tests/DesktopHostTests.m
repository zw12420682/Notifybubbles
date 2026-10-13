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
        UIView *touch=[[UIView alloc] initWithFrame:CGRectMake(100,100,60,60)]; [desktop addSubview:touch];
        Check(NFBShowDesktopInSplit(anchor),@"open");
        Check(NFBDesktopSplitActive() && desktop.superview!=root.view,@"real view transferred");
        Check(desktop.userInteractionEnabled && desktop.translatesAutoresizingMaskIntoConstraints,@"native touches enabled");
        Check(self.window.isKeyWindow,@"original focus preserved");
        for (NSLayoutConstraint *constraint in constraints) Check(!constraint.active,@"external constraints detached");
        CGPoint point=[touch convertPoint:CGPointMake(30,30) toView:desktop.window];
        Check([desktop.window hitTest:point withEvent:nil]==touch,@"scaled hit testing reaches native child");
        Check([desktop.window hitTest:CGPointMake(1,1) withEvent:nil]==nil,@"outside panel passes through");
        NFBCloseDesktopSplit(); NFBCloseDesktopSplit();
        Check(!NFBDesktopSplitActive() && desktop.superview==root.view,@"idempotent restore");
        Check([root.view.subviews indexOfObjectIdenticalTo:desktop]==index,@"original order");
        Check(CGRectEqualToRect(desktop.bounds,bounds) && CGPointEqualToPoint(desktop.center,center),@"original geometry");
        Check(CGAffineTransformIsIdentity(desktop.transform) && !desktop.userInteractionEnabled &&
            !desktop.translatesAutoresizingMaskIntoConstraints,@"original flags");
        for (NSLayoutConstraint *constraint in constraints) Check(constraint.active,@"constraints restored");
        Check(NFBShowDesktopInSplit(anchor),@"reopen");
        [SBLockScreenManager sharedInstance].locked=YES; NFBUpdateDesktopSplit(YES);
        Check(!NFBDesktopSplitActive() && desktop.superview==root.view,@"lock restores desktop");
        [SBLockScreenManager sharedInstance].locked=NO;
        Check(NFBShowDesktopInSplit(anchor),@"open before app launch");
        state.home=NO; NFBUpdateDesktopSplit(YES);
        Check(!NFBDesktopSplitActive(),@"app launch restores desktop"); state.home=YES;
        Check(NFBShowDesktopInSplit(anchor),@"open before disabling");
        NFBUpdateDesktopSplit(NO); Check(!NFBDesktopSplitActive(),@"disabled closes");
        CGRect good=anchor.frame; anchor.frame=CGRectMake(30,200,380,180);
        Check(!NFBShowDesktopInSplit(anchor),@"invalid geometry rejected");
        Check(desktop.superview==root.view && CGAffineTransformIsIdentity(desktop.transform) &&
            CGRectEqualToRect(desktop.bounds,bounds),@"failed preflight does not mutate desktop"); anchor.frame=good;
    } @catch (NSException *exception) { result=[NSString stringWithFormat:@"FAIL: %@",exception]; }
    NFBCloseDesktopSplit();
    NSString *path=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/desktop-test-result.txt"];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"%@",result);
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TestDelegate.class)); } }
