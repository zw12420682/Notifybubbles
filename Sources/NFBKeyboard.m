#import "NFBWindowState.h"
#import "NFBKeyboard.h"
#import "NFBColumnMotionPolicy.h"
#import "NFBPrivate.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// Notification + hide-confirmation state (pure decisions in the policy header).
static NFBKeyboardTrack NFBKeyboardTrackState;
// Timestamp of the last WillHide, used to override the probe grace window.
static CFTimeInterval NFBKeyboardHiddenSince;
static CGRect NFBKeyboardScreenFrame;
CGFloat NFBKeyboardTopInView(UIView *root) {
    if (!NFBKeyboardVisible()) return CGRectGetHeight(root.bounds);
    if (!CGRectIsEmpty(NFBKeyboardScreenFrame)) {
        CGRect frame = [root convertRect:NFBKeyboardScreenFrame fromView:nil];
        if (CGRectIntersectsRect(root.bounds, frame)) return MAX(0, CGRectGetMinY(frame));
    }
    // Remote keyboards may not publish their frame to SpringBoard. Keep the
    // entire lower 60% free rather than pretending the keyboard has a known height.
    return CGRectGetHeight(root.bounds) * 0.40;
}
static void (^NFBKeyboardChange)(void);

static void NFBKeyboardScheduleChange(void) {
    static BOOL queued;
    if (queued) return;
    queued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        queued = NO;
        if (NFBKeyboardChange) NFBKeyboardChange();
    });
}
static void NFBKeyboardUpdateFrame(NSValue *value) {
    if (!value || strcmp(value.objCType, @encode(CGRect))) return;
    CGRect frame = value.CGRectValue;
    if (CGRectEqualToRect(frame, NFBKeyboardScreenFrame)) return;
    NFBKeyboardScreenFrame = frame;
    NFBKeyboardScheduleChange();
}

// A keyboard window among SpringBoard's own windows. Conservative: the window
// must be visible and keyboard-sized, otherwise a permanently present-but-empty
// placeholder would keep the bubbles retracted forever.
static BOOL NFBKeyboardWindowUp(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (![app respondsToSelector:@selector(connectedScenes)]) return NO;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha <= 0.01) continue;
            NSString *name = NSStringFromClass(window.class);
            // UITextEffectsWindow is present in SpringBoard even with no keyboard
            // (it hosts the magnifier / text-selection handles), so it must never
            // count as a keyboard — matching it was keeping every bubble retracted.
            BOOL keyboard = [name isEqualToString:@"UIRemoteKeyboardWindow"] ||
                            [name isEqualToString:@"UIKeyboardWindow"];
            // A real keyboard spans the screen width and is tall; an empty
            // pre-created placeholder is tiny, so require a keyboard-sized frame.
            if (keyboard && window.bounds.size.height >= 100) return YES;
        }
    }
    return NO;
}

// Ask SpringBoard directly. The selector name differs between builds, so probe a
// few and take the first one that exists and returns a BOOL with no arguments.
static BOOL NFBKeyboardSystemUp(void) {
    id controller = NFBSingleton(@"SBUIController");
    if (!controller) return NO;
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"isKeyboardVisible", @"keyboardVisible", @"isKeyboardOnScreen"];
        // One-time survey so the debug file shows what the build really offers
        // if none of the guesses above match.
        NFBDumpMethods(controller, NO, @"SBUIController keyboard", @[@"keyboard"]);
    });
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if (![controller respondsToSelector:selector]) continue;
        NSMethodSignature *signature = NFBSignature(controller, selector);
        if (!signature || signature.numberOfArguments != 2) continue;
        char type = signature.methodReturnType[0];
        if (type != 'B' && type != 'c') continue;
        @try { return ((BOOL (*)(id, SEL))objc_msgSend)(controller, selector); }
        @catch (__unused NSException *error) { continue; }
    }
    return NO;
}

// Throttled probes with a hard TTL: an answer older than the TTL is not reused,
// it is re-probed (keyboards hosted by an app publish no notification here, so
// the probe is the only source that can recover the "up" state).
#define NFBKeyboardProbeInterval 0.2
#define NFBKeyboardProbeTTL 0.5

static BOOL NFBKeyboardProbeUp(void) {
    static BOOL window, system;
    static CFTimeInterval probedAt;
    static BOOL probed;
    CFTimeInterval now = CACurrentMediaTime();
    if (!probed || now - probedAt > NFBKeyboardProbeInterval) {
        probed = YES; probedAt = now;
        window = NFBKeyboardWindowUp();
        system = NFBKeyboardSystemUp();
    }
    // A stale answer can neither hold "up" nor certify "down".
    if (now - probedAt > NFBKeyboardProbeTTL) return NO;
    return window || system;
}

BOOL NFBKeyboardVisible(void) {
    // A collapse that has just been announced wins over the throttled probes,
    // which still see the keyboard window while it animates out.
    double now = CACurrentMediaTime();
    BOOL grace = NFBKeyboardHiddenGrace(now, NFBKeyboardHiddenSince);
    BOOL notified = NFBKeyboardTrackState.notified;
    BOOL probe = NFBKeyboardProbeUp();
    BOOL up = NFBKeyboardCombined(NFBKeyboardTrackState, probe, grace);
    // Log every flip, not just notification-driven ones, so a polled source
    // (window/system) that is stuck high shows up here with its per-source flags.
    static BOOL last = NO;
    static BOOL seen = NO;
    if (!seen || up != last) {
        seen = YES;
        last = up;
        NFBDebugLog(@"keyboard: %@ (notified=%d probe=%d grace=%d)", up ? @"up" : @"down", notified, probe, grace);
    }
    return up;
}

static void NFBKeyboardSet(NFBKeyboardTrack track, const char *source) {
    BOOL before = NFBKeyboardVisible();
    NFBKeyboardTrack previous = NFBKeyboardTrackState;
    NFBKeyboardTrackState = track;
    BOOL after = NFBKeyboardVisible();
    if (previous.notified != track.notified || previous.hiddenSince != track.hiddenSince)
        NFBDebugLog(@"keyboard: %s (notified=%d pending-hide=%d stale-did-hide=%d)", source,
                    track.notified, track.hiddenSince, track.staleDidHide);
    if (before == after) return;
    NFBKeyboardScheduleChange();
}

void NFBKeyboardInstall(void (^onChange)(void)) {
    // Plain C function, so NSAssert is unavailable here: it expands to `self`
    // and `_cmd`, which only exist inside a method.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ NFBKeyboardInstall(onChange); });
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NFBKeyboardChange = [onChange copy];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        NSOperationQueue *main = NSOperationQueue.mainQueue;
        void (^show)(NSNotification *) = ^(NSNotification *note) {
            NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
            NFBKeyboardUpdateFrame(value);
            NFBKeyboardHiddenSince = 0;   // a new keyboard cancels the hide grace
            NFBKeyboardSet(NFBKeyboardShow(NFBKeyboardTrackState, NO), "show");
        };
        void (^showDid)(NSNotification *) = ^(NSNotification *note) {
            NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
            NFBKeyboardUpdateFrame(value);
            // A duplicate DidShow after a hide announcement must not restart it.
            if (NFBKeyboardDidShowIsDuplicate(NFBKeyboardTrackState)) return;
            NFBKeyboardHiddenSince = 0;
            NFBKeyboardSet(NFBKeyboardShow(NFBKeyboardTrackState, NO), "did-show");
        };
        // Clearing the "visible" flag on WillHide slid the bubbles back down while
        // the keyboard was still on its way out, overlapping both animations. Only
        // DidHide ends keyboard mode; WillHide just records the target frame.
        void (^hideWill)(NSNotification *) = ^(NSNotification *note) {
            NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
            if (value) NFBKeyboardUpdateFrame(value);
            if (NFBKeyboardWillHideIsDuplicate(NFBKeyboardTrackState)) return;
            // Collapse starts here, not at DidHide: the bubbles should slide back
            // in while the keyboard is still on its way down. The window/scene
            // probes can keep reporting a keyboard for a few hundred ms after
            // WillHide, so suppress them for one animation's worth of time.
            NFBKeyboardHiddenSince = CACurrentMediaTime();
            NFBKeyboardTrackState.notified = NO;
            NFBKeyboardTrackState.hiddenSince = YES;
            if (NFBKeyboardChange) NFBKeyboardChange();
        };
        void (^hideDid)(NSNotification *) = ^(NSNotification *note) {
            NFBKeyboardUpdateFrame([NSValue valueWithCGRect:CGRectZero]);
            // A DidHide that no WillHide/DidShow announced belongs to a keyboard
            // that is already gone: it must not clear a newer WillShow.
            BOOL confirmed = NO;
            NFBKeyboardTrack track = NFBKeyboardDidHide(NFBKeyboardTrackState, &confirmed);
            if (!confirmed) {
                NFBKeyboardTrackState = track;
                NFBDebugLog(@"keyboard: stale did-hide ignored");
                return;
            }
            NFBKeyboardTrackState = track;
            NFBKeyboardSet(track, "did-hide");
        };
        [center addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:main usingBlock:^(NSNotification *note) {
            NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
            NFBKeyboardUpdateFrame(value);
        }];
        [center addObserverForName:UIKeyboardWillShowNotification object:nil queue:main usingBlock:show];
        [center addObserverForName:UIKeyboardDidShowNotification object:nil queue:main usingBlock:showDid];
        [center addObserverForName:UIKeyboardWillHideNotification object:nil queue:main usingBlock:hideWill];
        [center addObserverForName:UIKeyboardDidHideNotification object:nil queue:main usingBlock:hideDid];
        NFBDebugLog(@"keyboard: observers installed");
    });
}
