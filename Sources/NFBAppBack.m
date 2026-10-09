#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "NFBBackProtocol.h"
#import "NFBDebugLog.h"
#import <dlfcn.h>
#import <mach/mach_time.h>
#include <notify.h>

// Private UIKit entry points are probed before use; no touch structure offsets.
@interface UITouch (NFBSyntheticTouch)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setGestureView:(UIView *)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)time;
- (void)_setLocationInWindow:(CGPoint)point resetPrevious:(BOOL)reset;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setEdgeType:(NSInteger)edge;
- (void)_setHidEvent:(CFTypeRef)event;
@end
@interface UIApplication (NFBSyntheticTouch)
- (UIEvent *)_touchesEvent;
@end
@interface UIEvent (NFBSyntheticTouch)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(CFTypeRef)event;
- (void)_setTimestamp:(NSTimeInterval)timestamp;
@end

typedef CFTypeRef (*NFBHandFactory)(CFAllocatorRef,uint64_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,double,double,double,double,double,Boolean,Boolean,uint32_t);
typedef CFTypeRef (*NFBFingerFactory)(CFAllocatorRef,uint64_t,uint32_t,uint32_t,uint32_t,double,double,double,double,double,Boolean,Boolean,uint32_t);
static NFBHandFactory makeHand;
static NFBFingerFactory makeFinger;
static void (*appendFinger)(CFTypeRef,CFTypeRef,uint32_t);
static void (*setInteger)(CFTypeRef,uint32_t,CFIndex);
static BOOL NFBLoadTouchAPI(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (!lib) return;
        makeHand = (NFBHandFactory)dlsym(lib, "IOHIDEventCreateDigitizerEvent");
        makeFinger = (NFBFingerFactory)dlsym(lib, "IOHIDEventCreateDigitizerFingerEvent");
        appendFinger = (void (*)(CFTypeRef,CFTypeRef,uint32_t))dlsym(lib, "IOHIDEventAppendEvent");
        setInteger = (void (*)(CFTypeRef,uint32_t,CFIndex))dlsym(lib, "IOHIDEventSetIntegerValue");
    });
    return makeHand && makeFinger && appendFinger && setInteger;
}
static BOOL NFBWindowReady(UIWindow *window) {
    return window && !window.hidden && window.alpha > 0.01 && window.rootViewController &&
        CGRectGetWidth(window.bounds) > 40 && CGRectGetHeight(window.bounds) > 80;
}
static UIWindow *NFBTargetWindow(void) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    UIWindow *fallback = nil;
    for (UIWindow *w in windows) {
        if (!NFBWindowReady(w) || w.windowLevel != UIWindowLevelNormal) continue;
        if (w.isKeyWindow) return w;
        if (!fallback) fallback = w;
    }
    return fallback;
}
@interface NFBEdgeSwipe : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UITouch *touch;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) void (^completion)(uint8_t);
@property(nonatomic) CGRect originalBounds;
@property(nonatomic) CGPoint start;
@property(nonatomic) CGPoint end;
@property(nonatomic) NSUInteger frame;
@property(nonatomic) BOOL finished;
- (BOOL)deliver:(UITouchPhase)phase point:(CGPoint)point;
- (void)step;
- (void)finish:(uint8_t)status;
@end
static NFBEdgeSwipe *runningSwipe;
@implementation NFBEdgeSwipe
- (BOOL)deliver:(UITouchPhase)phase point:(CGPoint)point {
    CFTypeRef hand = NULL, finger = NULL;
    BOOL sent = NO;
    @try {
        NSTimeInterval timestamp = NSProcessInfo.processInfo.systemUptime;
        [self.touch setTimestamp:timestamp];
        [self.touch _setLocationInWindow:point resetPrevious:phase == UITouchPhaseBegan];
        [self.touch setPhase:phase];
        BOOL down = phase != UITouchPhaseEnded && phase != UITouchPhaseCancelled;
        uint32_t mask = phase == UITouchPhaseMoved ? 4 : 3;
        if (phase == UITouchPhaseCancelled) mask |= 0x80;
        uint64_t now = mach_absolute_time();
        hand = makeHand(kCFAllocatorDefault, now, 3, 0, 0, mask, 0, 0, 0, 0, 0, 0, down, down, 0);
        finger = makeFinger(kCFAllocatorDefault, now, 1, 2, mask, point.x, point.y, 0, 0, 0, down, down, 0);
        if (hand && finger) {
            setInteger(hand, (11 << 16) + 25, 1);
            setInteger(finger, (11 << 16) + 25, 1);
            appendFinger(hand, finger, 0);
            [self.touch _setHidEvent:hand];
            UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
            [event _clearTouches];
            [event _setHIDEvent:hand];
            if ([event respondsToSelector:@selector(_setTimestamp:)]) [event _setTimestamp:timestamp];
            [event _addTouch:self.touch forDelayedDelivery:NO];
            [UIApplication.sharedApplication sendEvent:event];
            sent = YES;
        }
    } @catch (NSException *e) { NFBErrorLog(@"edge swipe event failed: %@", e); }
    if (finger) CFRelease(finger);
    if (hand) CFRelease(hand);
    return sent;
}
- (void)finish:(uint8_t)status {
    if (self.finished) return;
    self.finished = YES;
    if (self.touch.phase == UITouchPhaseBegan || self.touch.phase == UITouchPhaseMoved || self.touch.phase == UITouchPhaseStationary)
        [self deliver:UITouchPhaseCancelled point:[self.touch locationInView:self.window]];
    [self.timer invalidate]; self.timer = nil;
    void (^done)(uint8_t) = self.completion; self.completion = nil;
    if (runningSwipe == self) runningSwipe = nil;
    if (done) done(status);
}
- (void)step {
    if (self.finished) return;
    if (!NFBWindowReady(self.window) || !CGRectEqualToRect(self.window.bounds, self.originalBounds) || !self.touch.view.window) {
        [self deliver:UITouchPhaseCancelled point:[self.touch locationInView:self.window]];
        [self finish:NFBBackStatusTransitioning]; return;
    }
    self.frame++;
    CGFloat progress = MIN(1, self.frame / 24.0);
    CGPoint point = CGPointMake(self.start.x + (self.end.x - self.start.x) * progress, self.start.y);
    UITouchPhase phase = self.frame >= 24 ? UITouchPhaseEnded : UITouchPhaseMoved;
    if (![self deliver:phase point:point]) {
        [self deliver:UITouchPhaseCancelled point:point];
        [self finish:NFBBackStatusException];
    } else if (phase == UITouchPhaseEnded) [self finish:NFBBackStatusPerformed];
}
@end
static void NFBPerformSwipe(void (^done)(uint8_t)) {
    if (runningSwipe) { done(NFBBackStatusTransitioning); return; }
    UIWindow *window = NFBTargetWindow();
    if (!window) { done(NFBBackStatusNoWindow); return; }
    UITouch *touch = [UITouch new];
    NSArray<NSString *> *touchSelectors = @[@"setWindow:", @"setView:", @"setTapCount:", @"setPhase:", @"setTimestamp:", @"_setLocationInWindow:resetPrevious:", @"_setHidEvent:", @"_setEdgeType:"];
    for (NSString *name in touchSelectors) if (![touch respondsToSelector:NSSelectorFromString(name)]) { done(NFBBackStatusNoBackAction); return; }
    UIApplication *app = UIApplication.sharedApplication;
    if (!NFBLoadTouchAPI() || ![app respondsToSelector:@selector(_touchesEvent)]) { done(NFBBackStatusNoBackAction); return; }
    UIEvent *event = [app _touchesEvent];
    for (NSString *name in @[@"_clearTouches", @"_setHIDEvent:", @"_addTouch:forDelayedDelivery:"])
        if (![event respondsToSelector:NSSelectorFromString(name)]) { done(NFBBackStatusNoBackAction); return; }
    for (UITouch *existing in event.allTouches)
        if (existing.phase != UITouchPhaseEnded && existing.phase != UITouchPhaseCancelled) { done(NFBBackStatusTransitioning); return; }
    CGRect bounds = window.bounds;
    // App-local coordinates automatically follow TrollOpen's hosting scale/position.
    CGFloat y = CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * 0.42;
    CGPoint start = CGPointMake(CGRectGetMinX(bounds) + 1, y);
    UIView *hit = [window hitTest:start withEvent:nil];
    if (!hit) { done(NFBBackStatusNoWindow); return; }
    @try {
        [touch setWindow:window];
        [touch setView:hit];
        if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:hit];
        [touch setTapCount:1];
        [touch _setEdgeType:4];
        if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) [touch _setIsFirstTouchForView:YES];
        NFBEdgeSwipe *swipe = [NFBEdgeSwipe new];
        swipe.window = window; swipe.touch = touch; swipe.completion = done;
        swipe.originalBounds = bounds; swipe.start = start;
        swipe.end = CGPointMake(CGRectGetMinX(bounds) + CGRectGetWidth(bounds) * 0.78, y);
        runningSwipe = swipe;
        if (![swipe deliver:UITouchPhaseBegan point:start]) { [swipe finish:NFBBackStatusException]; return; }
        swipe.timer = [NSTimer timerWithTimeInterval:1.0/60.0 target:swipe selector:@selector(step) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:swipe.timer forMode:NSRunLoopCommonModes];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!swipe.finished) [swipe finish:NFBBackStatusTransitioning];
        });
    } @catch (NSException *e) {
        NFBErrorLog(@"edge swipe start failed: %@", e);
        if (runningSwipe) [runningSwipe finish:NFBBackStatusException]; else done(NFBBackStatusException);
    }
}
__attribute__((constructor)) static void NFBInstallAppBack(void) {
    @autoreleasepool {
        NSString *app = NSBundle.mainBundle.bundleIdentifier;
        if (!app.length || [app isEqual:@"com.apple.springboard"] ||
            ![NSBundle.mainBundle.bundlePath hasSuffix:@".app"] || NSBundle.mainBundle.infoDictionary[@"NSExtension"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *name = NFBBackName(app), *reply = [name stringByAppendingString:@".reply"];
            __block uint64_t previous = 0;
            int token = 0;
            notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int input) {
                uint64_t request = 0;
                if (notify_get_state(input, &request) != NOTIFY_STATUS_OK || request == previous || !NFBBackFresh(request, NFBBackTime())) return;
                previous = request;
                NFBPerformSwipe(^(uint8_t status) {
                    NFBDebugLog(@"edge swipe finished app=%@ status=%u", app, (unsigned)status);
                    int response = 0;
                    if (notify_register_check(reply.UTF8String, &response) == NOTIFY_STATUS_OK) {
                        notify_set_state(response, (request << NFBBackStatusShift) | (status & 0xF));
                        notify_post(reply.UTF8String); notify_cancel(response);
                    }
                });
            });
        });
    }
}
