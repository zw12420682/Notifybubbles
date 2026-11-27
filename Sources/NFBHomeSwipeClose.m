#import "NFBHomeSwipeClose.h"
#import "NFBHomeSwipePolicy.h"
#import "NFBWindowControls.h"
#import "NFBWindowState.h"
#import "NFBSplitCoordinator.h"
#import "NFBPrivate.h"
#import "NFBDebugLog.h"
#import <objc/runtime.h>
#ifndef NFB_HOME_SWIPE_TEST
#import <substrate.h>
#else
extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
#endif

// Verified declarations bracket iOS 16 (15.5 and 17.0); installation additionally
// requires the complete live ABI on iOS 16. Device callback coverage is separate
// from these signatures and from the UIKit fixture.
typedef void (*NFBPullIMP)(id, SEL, id, double, double, id);
static NFBPullIMP NFBOriginalPull[4];
static BOOL NFBHomeSwipeEnabled;
static NSUInteger NFBHomeSwipeConfiguration;
static char NFBHomeSwipeSessionKey;

@interface NFBHomeSwipeSession : NSObject
@property(nonatomic,weak) id tongue;
@property(nonatomic,weak) UIPanGestureRecognizer *recognizer;
@property(nonatomic,weak) UIView *target, *parent, *region;
@property(nonatomic,weak) UIWindow *host;
@property(nonatomic,copy) NSString *bundle, *sceneKey;
@property(nonatomic) NSUInteger operationEpoch, configuration;
@property(nonatomic) BOOL invalid, finished;
@end
@implementation NFBHomeSwipeSession @end

void NFBConfigureHomeSwipeClose(BOOL enabled) {
    NSCAssert(NSThread.isMainThread, @"home swipe configuration requires main queue");
    if (NFBHomeSwipeEnabled != enabled) ++NFBHomeSwipeConfiguration;
    NFBHomeSwipeEnabled = enabled;
}
static BOOL NFBHomeSwipeUnlocked(void) {
    id lock = NFBSingleton(@"SBLockScreenManager");
    return lock && !NFBCheckedBool(lock, @"isUILocked", YES);
}
static BOOL NFBHomeSwipeSessionValid(NFBHomeSwipeSession *session) {
    if (session.invalid || !NFBHomeSwipeEnabled || !NFBHomeSwipeUnlocked() ||
        session.configuration != NFBHomeSwipeConfiguration ||
        session.operationEpoch != NFBSplitCoordinator.shared.operationEpoch) return NO;
    UIView *target = session.target;
    NFBWindowState *state = NFBCurrentWindowState();
    return target && session.host && target.window == session.host && target.superview == session.parent &&
        !target.hidden && target.alpha > 0.01 &&
        [NFBString(NFBGet(target, @"bundleID")) isEqualToString:session.bundle] &&
        [state.sceneKey isEqualToString:session.sceneKey] &&
        NFBGet(target, @"rightTouchRegion") == session.region && session.region != nil &&
        !NFBCheckedBool(target, @"miniWindowModeEnabled", YES) &&
        !NFBCheckedBool(target, @"isTransitioningFromMiniMode", YES) &&
        !NFBCheckedBool(target, @"isClosingWithKeepAliveAnimation", YES);
}
// Diagnostic only. This record is never an owned gesture session.
static __weak id nfbRejectTongue;
static __weak UIPanGestureRecognizer *nfbRejectPan;
static __weak UIView *nfbRejectWindow;
static NSString *nfbRejectFront, *nfbRejectSplit;
static BOOL nfbRejectHome, nfbRejectHadWindow, nfbRejectEnded;
static NSUInteger nfbRejectSequence, nfbRejectConfiguration;
static CFTimeInterval nfbRejectAt, nfbRejectEndAt;
static CGFloat nfbRejectPeakUp;
static void NFBResetRejectTrace(void) {
    nfbRejectAt=0; nfbRejectEnded=NO; nfbRejectTongue=nil; nfbRejectPan=nil;
    nfbRejectWindow=nil; nfbRejectSplit=nil; nfbRejectFront=nil;
}
static void NFBStartRejectTrace(id tongue,UIPanGestureRecognizer *pan) {
    if (!NFBDebugLoggingEnabled()) return;
    NFBWindowState *state=NFBCurrentWindowState();
    UIView *window=NFBHomeSwipeCloseWindow();
    nfbRejectTongue=tongue; nfbRejectPan=pan; nfbRejectWindow=window;
    nfbRejectFront=[state.frontApp copy]; nfbRejectSplit=[NFBString(NFBGet(window,@"bundleID")) copy];
    nfbRejectHome=state.home; nfbRejectHadWindow=window!=nil;
    nfbRejectConfiguration=NFBHomeSwipeConfiguration;
    nfbRejectSequence++; nfbRejectPeakUp=0; nfbRejectAt=CACurrentMediaTime(); nfbRejectEnded=NO;
    NFBDebugLog(@"swipe-pass: began id=%lu front=%@ home=%d portrait=%@",(unsigned long)nfbRejectSequence,nfbRejectFront,nfbRejectHome,nfbRejectSplit);
}
static void NFBObserveRejectPhase(id tongue,NSUInteger phase) {
    if (!nfbRejectAt || nfbRejectEnded || tongue!=nfbRejectTongue || !phase) return;
    if (!NFBDebugLoggingEnabled() || CACurrentMediaTime()-nfbRejectAt>8 || nfbRejectConfiguration!=NFBHomeSwipeConfiguration) { NFBResetRejectTrace(); return; }
    UIPanGestureRecognizer *pan=nfbRejectPan;
    if (!pan || !pan.view || NFBGet(tongue,@"edgePullGestureRecognizer")!=pan) return;
    CGPoint p=[pan translationInView:pan.view]; nfbRejectPeakUp=MAX(nfbRejectPeakUp,-p.y);
    if (phase<2) return;
    nfbRejectEnded=YES; nfbRejectEndAt=CACurrentMediaTime();
    NFBDebugLog(@"swipe-pass: end id=%lu cancelled=%d translation=%@ peakUp=%.1f",(unsigned long)nfbRejectSequence,phase==3,NSStringFromCGPoint(p),nfbRejectPeakUp);
}
void NFBObserveRejectedSwipeResult(void) {
    if (!nfbRejectAt) return;
    @try {
        CFTimeInterval now=CACurrentMediaTime();
        if (!NFBDebugLoggingEnabled() || !NFBHomeSwipeEnabled || !NFBHomeSwipeUnlocked() || nfbRejectConfiguration!=NFBHomeSwipeConfiguration || now-nfbRejectAt>8) { NFBResetRejectTrace(); return; }
        if (!nfbRejectEnded || now-nfbRejectEndAt<0.25) return;
        NFBWindowState *state=NFBCurrentWindowState(); UIView *current=NFBHomeSwipeCloseWindow();
        NFBDebugLog(@"swipe-pass: settled id=%lu frontBefore=%@ frontAfter=%@ home=%d->%d portraitBefore=%@ portraitAfter=%@ sameWindow=%d lag=%.2f",(unsigned long)nfbRejectSequence,nfbRejectFront,state.frontApp,nfbRejectHome,state.home,nfbRejectSplit,NFBString(NFBGet(current,@"bundleID")),nfbRejectHadWindow && current && current==nfbRejectWindow,now-nfbRejectEndAt);
    } @catch (__unused NSException *error) {}
    NFBResetRejectTrace();
}
static NFBHomeSwipeSession *NFBHomeSwipeBegin(id manager, id tongue, double distance, double velocity) {
    if (!NFBHomeSwipeEnabled || !NFBHomeSwipeUnlocked() ||
        NFBGet(manager, @"deckGrabberTongue") != tongue) return nil;
    id value = NFBGet(tongue, @"edgePullGestureRecognizer");
    if (![value isKindOfClass:UIPanGestureRecognizer.class] ||
        value != NFBGet(manager, @"homeGestureBottomEdgeRecognizer")) return nil;
    UIPanGestureRecognizer *recognizer = value;
    if (recognizer.state != UIGestureRecognizerStateBegan || !recognizer.view) return nil;
    CGPoint translation = [recognizer translationInView:recognizer.view];
    CGPoint speed = [recognizer velocityInView:recognizer.view];
    if (!NFBHomeSwipeCanCapture(translation.x, translation.y, speed.x, speed.y, distance, velocity)) {
        NFBStartRejectTrace(tongue,recognizer);
        NFBDebugLog(@"home-swipe: begin rejected translation=%@ velocity=%@ native=%.1f/%.1f",
            NSStringFromCGPoint(translation), NSStringFromCGPoint(speed), distance, velocity);
        return nil;
    }
    NFBInvalidateWindowState();
    UIView *target = NFBHomeSwipeCloseWindow();
    if (!target) return nil; // No proven native orange action: leave system alone.
    NFBHomeSwipeSession *session = [NFBHomeSwipeSession new];
    session.tongue = tongue; session.recognizer = recognizer;
    session.target = target; session.parent = target.superview; session.host = target.window;
    session.region = NFBGet(target, @"rightTouchRegion");
    session.bundle = NFBString(NFBGet(target, @"bundleID"));
    session.sceneKey = NFBCurrentWindowState().sceneKey;
    session.operationEpoch = NFBSplitCoordinator.shared.operationEpoch;
    session.configuration = NFBHomeSwipeConfiguration;
    if (!NFBHomeSwipeSessionValid(session)) return nil;
    NFBDebugLog(@"home-swipe: captured app=%@", session.bundle);
    return session;
}
static void NFBHomeSwipePull(id manager, SEL command, id tongue, double distance,
    double velocity, id gesture, NSUInteger phase) {
    if (!NSThread.isMainThread) {
        NFBOriginalPull[phase](manager, command, tongue, distance, velocity, gesture); return;
    }
    NFBHomeSwipeSession *session = objc_getAssociatedObject(manager, &NFBHomeSwipeSessionKey);
    if (phase == 0) {
        // A side tongue can begin while the bottom stream is still owned.
        // Pass it through without clearing the bottom stream or its tombstone.
        if (NFBGet(manager, @"deckGrabberTongue") != tongue) {
            NFBOriginalPull[phase](manager, command, tongue, distance, velocity, gesture); return;
        }
        // A new began is the only point where ownership can change. Retain the
        // finished tombstone through duplicate terminal callbacks of one stream.
        NFBResetRejectTrace();
        session = nil;
        @try { session = NFBHomeSwipeBegin(manager, tongue, distance, velocity); }
        @catch (NSException *error) { NFBErrorLog(@"home-swipe: begin %@", error); }
        objc_setAssociatedObject(manager, &NFBHomeSwipeSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!session || session.tongue != tongue) {
        @try { NFBObserveRejectPhase(tongue,phase); } @catch (__unused NSException *error) { NFBResetRejectTrace(); }
        NFBOriginalPull[phase](manager, command, tongue, distance, velocity, gesture); return;
    }
    // Suppress the whole owned stream, including invalid/cancelled tails. Never
    // forward an ended callback whose began did not reach the system transaction.
    if (session.finished) return;
    @try {
        NFBInvalidateWindowState();
        if (!NFBHomeSwipeSessionValid(session)) session.invalid = YES;
        if (phase < 2) return;
        session.finished = YES;
        UIPanGestureRecognizer *recognizer = session.recognizer;
        if (phase == 3 || session.invalid || !recognizer.view ||
            recognizer.state != UIGestureRecognizerStateEnded) {
            NFBDebugLog(@"home-swipe: cancelled app=%@", session.bundle); return;
        }
        CGPoint translation = [recognizer translationInView:recognizer.view];
        CGPoint speed = [recognizer velocityInView:recognizer.view];
        if (!NFBHomeSwipeCanFinish(translation.x, translation.y, speed.x, speed.y)) return;
        // Native single tap on the saved window ONLY; no global close-current,
        // scene relaunch, home-screen action, process termination or fallback.
        BOOL closed = NFBCloseHomeSwipeWindow(session.target);
        NFBDebugLog(@"home-swipe: orange-close=%d app=%@", closed, session.bundle);
    } @catch (NSException *error) {
        session.invalid = YES;
        if (phase >= 2) session.finished = YES;
        NFBErrorLog(@"home-swipe: owned %@", error);
    }
}
static void NFBHomeSwipeBegan(id self, SEL cmd, id tongue, double d, double v, id gesture) {
    NFBHomeSwipePull(self, cmd, tongue, d, v, gesture, 0);
}
static void NFBHomeSwipeUpdated(id self, SEL cmd, id tongue, double d, double v, id gesture) {
    NFBHomeSwipePull(self, cmd, tongue, d, v, gesture, 1);
}
static void NFBHomeSwipeEnded(id self, SEL cmd, id tongue, double d, double v, id gesture) {
    NFBHomeSwipePull(self, cmd, tongue, d, v, gesture, 2);
}
static void NFBHomeSwipeCancelled(id self, SEL cmd, id tongue, double d, double v, id gesture) {
    NFBHomeSwipePull(self, cmd, tongue, d, v, gesture, 3);
}
void NFBInstallHomeSwipeClose(void) {
    static BOOL installed;
    if (installed || !NSThread.isMainThread) return;
    Class cls = NSClassFromString(@"SBFluidSwitcherGestureManager");
    Class tongueClass = NSClassFromString(@"SBGrabberTongue");
    if (!cls || !tongueClass) return;
    const char *names[] = {
        "grabberTongueBeganPulling:withDistance:andVelocity:andGesture:",
        "grabberTongueUpdatedPulling:withDistance:andVelocity:andGesture:",
        "grabberTongueEndedPulling:withDistance:andVelocity:andGesture:",
        "grabberTongueCanceledPulling:withDistance:andVelocity:andGesture:"
    };
    Method methods[4];
    for (NSUInteger i = 0; i < 4; ++i) {
        methods[i] = class_getInstanceMethod(cls, sel_registerName(names[i]));
        if (!methods[i]) { NFBErrorLog(@"home-swipe: missing callback %s", names[i]); return; }
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(methods[i])];
        if (sig.numberOfArguments != 6 || strcmp(sig.methodReturnType, @encode(void)) ||
            strcmp([sig getArgumentTypeAtIndex:2], @encode(id)) ||
            strcmp([sig getArgumentTypeAtIndex:3], @encode(double)) ||
            strcmp([sig getArgumentTypeAtIndex:4], @encode(double)) ||
            strcmp([sig getArgumentTypeAtIndex:5], @encode(id))) {
            NFBErrorLog(@"home-swipe: incompatible callback %s", names[i]); return;
        }
    }
    Class classes[] = { cls, cls, tongueClass };
    const char *getters[] = { "deckGrabberTongue", "homeGestureBottomEdgeRecognizer", "edgePullGestureRecognizer" };
    for (NSUInteger i = 0; i < 3; ++i) {
        Method method = class_getInstanceMethod(classes[i], sel_registerName(getters[i]));
        if (!method) { NFBErrorLog(@"home-swipe: missing getter %s", getters[i]); return; }
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return;
    }
    // Validate the ENTIRE quartet first. Localize inherited methods so a hook
    // cannot affect another grabber delegate through a shared superclass.
    IMP replacements[] = { (IMP)NFBHomeSwipeBegan, (IMP)NFBHomeSwipeUpdated,
        (IMP)NFBHomeSwipeEnded, (IMP)NFBHomeSwipeCancelled };
    for (NSUInteger i = 0; i < 4; ++i) {
        SEL selector = sel_registerName(names[i]);
        class_addMethod(cls, selector, method_getImplementation(methods[i]), method_getTypeEncoding(methods[i]));
        MSHookMessageEx(cls, selector, replacements[i], (IMP *)&NFBOriginalPull[i]);
    }
    installed = YES;
    NFBInfoLog(@"home-swipe: installed bottom-edge quartet (live ABI verified)");
}
