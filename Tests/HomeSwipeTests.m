#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NFBHomeSwipeClose.h"
#import "NFBWindowState.h"
#import "NFBSplitCoordinator.h"
#import "NFBWindowControls.h"
#import "NFBDebugLog.h"

static NSUInteger hookCount, originalCalls, closeCalls, fixtureOperation;
static UIView *currentTarget, *lastClosed;
static NFBWindowState *fixtureState;
static BOOL locked;
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    *original = method_setImplementation(class_getInstanceMethod(cls,selector),replacement); ++hookCount;
}
BOOL NFBDebugLoggingEnabled(void) { return NO; }
void NFBWriteDebugLog(NSString *format, ...) { (void)format; }
void NFBInfoLog(NSString *format, ...) { (void)format; }
void NFBErrorLog(NSString *format, ...) { (void)format; }
@implementation NFBWindowState @end
NFBWindowState *NFBCurrentWindowState(void) { return fixtureState; }
void NFBInvalidateWindowState(void) {}
UIView *NFBHomeSwipeCloseWindow(void) { return currentTarget; }
BOOL NFBCloseHomeSwipeWindow(UIView *target) {
    if (target != currentTarget) return NO;
    lastClosed = target; ++closeCalls; return YES;
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
@implementation NFBSplitCoordinator
+ (instancetype)shared { static id shared; if (!shared) shared=[self new]; return shared; }
- (NSUInteger)operationEpoch { return fixtureOperation; }
- (NSUInteger)generation { return fixtureOperation+100; }
@end
#pragma clang diagnostic pop

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end
@implementation SBLockScreenManager
+ (instancetype)sharedInstance { static id shared; if (!shared) shared=[self new]; return shared; }
- (BOOL)isUILocked { return locked; }
@end
@interface NFBHomeSwipeTestTarget : UIView
@property(nonatomic,copy) NSString *bundleID;
@property(nonatomic,strong) UIView *rightTouchRegion;
@property(nonatomic) BOOL miniWindowModeEnabled, isTransitioningFromMiniMode, isClosingWithKeepAliveAnimation;
@end
@implementation NFBHomeSwipeTestTarget @end
@interface NFBHomeSwipeTestPan : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState fixtureState;
@property(nonatomic) CGPoint fixtureTranslation, fixtureVelocity;
@end
@implementation NFBHomeSwipeTestPan
- (UIGestureRecognizerState)state { return self.fixtureState; }
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.fixtureTranslation; }
- (CGPoint)velocityInView:(UIView *)view { (void)view; return self.fixtureVelocity; }
@end
@interface SBGrabberTongue : NSObject
@property(nonatomic,strong) id edgePullGestureRecognizer;
@end
@implementation SBGrabberTongue @end
@interface SBFluidSwitcherGestureManager : NSObject
@property(nonatomic,strong) id deckGrabberTongue;
- (id)homeGestureBottomEdgeRecognizer;
- (void)grabberTongueBeganPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g;
- (void)grabberTongueUpdatedPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g;
- (void)grabberTongueEndedPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g;
- (void)grabberTongueCanceledPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g;
@end
@implementation SBFluidSwitcherGestureManager
- (id)homeGestureBottomEdgeRecognizer { return [self.deckGrabberTongue edgePullGestureRecognizer]; }
- (void)grabberTongueBeganPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g {
    (void)t; (void)d; (void)v; (void)g; ++originalCalls;
}
- (void)grabberTongueUpdatedPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g {
    (void)t; (void)d; (void)v; (void)g; ++originalCalls;
}
- (void)grabberTongueEndedPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g {
    (void)t; (void)d; (void)v; (void)g; ++originalCalls;
}
- (void)grabberTongueCanceledPulling:(id)t withDistance:(double)d andVelocity:(double)v andGesture:(id)g {
    (void)t; (void)d; (void)v; (void)g; ++originalCalls;
}
@end
static void NFBCheck(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"NFBHomeSwipeTestFailure" format:@"%@",message];
}
static void NFBTestPhase(SBFluidSwitcherGestureManager *m, NFBHomeSwipeTestPan *pan, NSUInteger phase) {
    pan.fixtureState=phase==0?UIGestureRecognizerStateBegan:phase==1?UIGestureRecognizerStateChanged:
        phase==2?UIGestureRecognizerStateEnded:UIGestureRecognizerStateCancelled;
    if (phase==0) pan.fixtureTranslation=CGPointMake(0,-10);
    else pan.fixtureTranslation=CGPointMake(0,-100);
    pan.fixtureVelocity=CGPointMake(0,-700);
    id t=m.deckGrabberTongue;
    switch (phase) {
        case 0:[m grabberTongueBeganPulling:t withDistance:10 andVelocity:700 andGesture:pan];break;
        case 1:[m grabberTongueUpdatedPulling:t withDistance:100 andVelocity:700 andGesture:pan];break;
        case 2:[m grabberTongueEndedPulling:t withDistance:100 andVelocity:700 andGesture:pan];break;
        default:[m grabberTongueCanceledPulling:t withDistance:100 andVelocity:700 andGesture:pan];break;
    }
}
static void NFBRunHomeSwipeTests(UIWindow *host) {
    NFBInstallHomeSwipeClose(); NFBCheck(hookCount==4,@"install complete quartet");
    NFBInstallHomeSwipeClose(); NFBCheck(hookCount==4,@"idempotent install");
    NFBConfigureHomeSwipeClose(YES);
    NFBHomeSwipeTestTarget *target=[[NFBHomeSwipeTestTarget alloc] initWithFrame:CGRectMake(0,0,200,300)];
    target.bundleID=@"test.B"; target.rightTouchRegion=[UIView new]; [target addSubview:target.rightTouchRegion];
    [host.rootViewController.view addSubview:target];
    fixtureState=[NFBWindowState new]; fixtureState.sceneKey=@"test.A|test.B|1|0";
    fixtureState.frontApp=@"test.A"; fixtureState.floatingWindow=target;
    currentTarget=target;
    NFBHomeSwipeTestPan *pan=[NFBHomeSwipeTestPan new]; [host.rootViewController.view addGestureRecognizer:pan];
    SBGrabberTongue *tongue=[SBGrabberTongue new]; tongue.edgePullGestureRecognizer=pan;
    SBFluidSwitcherGestureManager *manager=[SBFluidSwitcherGestureManager new]; manager.deckGrabberTongue=tongue;
    NFBTestPhase(manager,pan,0); NFBTestPhase(manager,pan,1); NFBTestPhase(manager,pan,2);
    NFBCheck(closeCalls==1 && lastClosed==target && originalCalls==0,@"B closes once; A gets no system callback");
    NFBTestPhase(manager,pan,2); NFBTestPhase(manager,pan,3);
    NFBCheck(closeCalls==1 && originalCalls==0,@"duplicate terminal cannot close twice or leak to system");
    currentTarget=nil;
    NFBTestPhase(manager,pan,0); NFBTestPhase(manager,pan,1); NFBTestPhase(manager,pan,2);
    NFBCheck(originalCalls==3 && closeCalls==1,@"no split: complete original system stream");
    currentTarget=target; NSUInteger native=originalCalls;
    NFBTestPhase(manager,pan,0); NFBTestPhase(manager,pan,3); NFBTestPhase(manager,pan,2);
    NFBCheck(closeCalls==1 && originalCalls==native,@"cancel consumes tail without closing or returning A home");
    for (NSUInteger scenario=0; scenario<9; ++scenario) {
        currentTarget=target; target.hidden=NO; target.miniWindowModeEnabled=NO;
        target.isClosingWithKeepAliveAnimation=NO; target.bundleID=@"test.B";
        fixtureState.sceneKey=@"test.A|test.B|1|0"; locked=NO; NFBConfigureHomeSwipeClose(YES);
        NFBTestPhase(manager,pan,0);
        switch (scenario) {
            case 0: fixtureOperation++; break;
            case 1: fixtureState.sceneKey=@"test.A|test.C|1|0"; break;
            case 2: target.bundleID=@"test.C"; break;
            case 3: target.miniWindowModeEnabled=YES; break;
            case 4: target.hidden=YES; break;
            case 5: locked=YES; break;
            case 6: NFBConfigureHomeSwipeClose(NO); NFBConfigureHomeSwipeClose(YES); break;
            case 7: target.isClosingWithKeepAliveAnimation=YES; break;
            default: [target removeFromSuperview]; break;
        }
        NFBTestPhase(manager,pan,1);
        // Even a temporary change that has reverted must invalidate this pull.
        target.bundleID=@"test.B"; target.hidden=NO; target.miniWindowModeEnabled=NO;
        target.isClosingWithKeepAliveAnimation=NO; fixtureState.sceneKey=@"test.A|test.B|1|0"; locked=NO;
        if (!target.superview) [host.rootViewController.view addSubview:target];
        NFBTestPhase(manager,pan,2);
        NFBCheck(closeCalls==1 && originalCalls==native,@"changed owned gesture never retargets or forwards a tail");
    }
    locked=YES; NFBTestPhase(manager,pan,0); NFBTestPhase(manager,pan,2);
    NFBCheck(originalCalls==native+2 && closeCalls==1,@"locked: original stream"); native=originalCalls; locked=NO;
    NFBConfigureHomeSwipeClose(NO); NFBTestPhase(manager,pan,0); NFBTestPhase(manager,pan,2);
    NFBCheck(originalCalls==native+2 && closeCalls==1,@"disabled: original stream"); native=originalCalls;
    NFBConfigureHomeSwipeClose(YES);
    NFBTestPhase(manager,pan,0);
    pan.fixtureState=UIGestureRecognizerStateEnded; pan.fixtureTranslation=CGPointMake(0,-10);
    [manager grabberTongueEndedPulling:tongue withDistance:10 andVelocity:0 andGesture:pan];
    NFBCheck(closeCalls==1 && originalCalls==native,@"short pull not accepted");
    NFBTestPhase(manager,pan,0);
    currentTarget=[UIView new]; NFBTestPhase(manager,pan,2); currentTarget=target;
    NFBCheck(closeCalls==1 && originalCalls==native,@"final native dispatcher rechecks exact saved target");
    NFBTestPhase(manager,pan,0);
    SBGrabberTongue *other=[SBGrabberTongue new];
    [manager grabberTongueBeganPulling:other withDistance:1 andVelocity:1 andGesture:pan];
    [manager grabberTongueUpdatedPulling:other withDistance:1 andVelocity:1 andGesture:pan];
    NFBCheck(originalCalls==native+2,@"other tongue unaffected during owned bottom pull");
    NFBTestPhase(manager,pan,3);
    NFBCheck(originalCalls==native+2 && closeCalls==1,@"side began cannot discard bottom ownership");
    pan.fixtureState=UIGestureRecognizerStateBegan; pan.fixtureTranslation=CGPointZero;
    pan.fixtureVelocity=CGPointMake(0,-100);
    [manager grabberTongueBeganPulling:tongue withDistance:5 andVelocity:100 andGesture:pan];
    pan.fixtureState=UIGestureRecognizerStateEnded; pan.fixtureTranslation=CGPointMake(0,-50);
    [manager grabberTongueEndedPulling:tongue withDistance:50 andVelocity:100 andGesture:pan];
    NFBCheck(closeCalls==2 && originalCalls==native+2,@"zero translation began and gentle 50pt swipe close immediately");
    double samples[][6]={{15,-5,449.88,-149.96,20,150},
        {-6,-5.6667,-60.1178,-56.778,20.7,56.8},{5,-5,85.853,-85.853,20,85.9},
        {-8,-1,-120.04,-15,19.7,15},{5.3333,-1.3333,64.017,-16.004,18.3,16}};
    for (NSUInteger i=0;i<3;++i) {
        pan.fixtureState=UIGestureRecognizerStateBegan;
        pan.fixtureTranslation=CGPointMake(samples[i][0],samples[i][1]);
        pan.fixtureVelocity=CGPointMake(samples[i][2],samples[i][3]);
        [manager grabberTongueBeganPulling:tongue withDistance:samples[i][4] andVelocity:samples[i][5] andGesture:pan];
        NFBTestPhase(manager,pan,2);
        NFBCheck(closeCalls==3+i && originalCalls==native+2,@"device diagonal began closes B without forwarding system home for A");
    }
    NFBCheck([fixtureState.frontApp isEqualToString:@"test.A"],@"underlying A identity preserved");
}
@interface NFBHomeSwipeTestApp : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation NFBHomeSwipeTestApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[UIViewController new]; [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *result=@"PASS";
        @try { NFBRunHomeSwipeTests(self.window); }
        @catch(NSException *error) { result=error.description; }
        NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        [result writeToFile:[folder stringByAppendingPathComponent:@"home-swipe-test-result.txt"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(NFBHomeSwipeTestApp.class)); }
}
