#import "NFBKeyboard.h"
#import "NFBPrivate.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>

// Set from the notifications, which only cover keyboards SpringBoard hosts.
static BOOL NFBKeyboardNotified = NO;
static void (^NFBKeyboardChange)(void);

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
        NSMethodSignature *signature = [controller methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2) continue;
        char type = signature.methodReturnType[0];
        if (type != 'B' && type != 'c') continue;
        @try { return ((BOOL (*)(id, SEL))objc_msgSend)(controller, selector); }
        @catch (__unused NSException *error) { continue; }
    }
    return NO;
}

BOOL NFBKeyboardVisible(void) {
    BOOL notified = NFBKeyboardNotified;
    BOOL window = NFBKeyboardWindowUp();
    BOOL system = NFBKeyboardSystemUp();
    BOOL up = notified || window || system;
    // Log every flip, not just notification-driven ones, so a polled source
    // (window/system) that is stuck high shows up here with its per-source flags.
    static BOOL last = NO;
    static BOOL seen = NO;
    if (!seen || up != last) {
        seen = YES;
        last = up;
        NFBDebugLog(@"keyboard: %@ (notified=%d window=%d system=%d)", up ? @"up" : @"down", notified, window, system);
    }
    return up;
}

static void NFBKeyboardSet(BOOL notified) {
    BOOL before = NFBKeyboardVisible();
    NFBKeyboardNotified = notified;
    BOOL after = NFBKeyboardVisible();
    if (before == after) return;
    if (NFBKeyboardChange) NFBKeyboardChange();
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
        void (^show)(NSNotification *) = ^(__unused NSNotification *note) { NFBKeyboardSet(YES); };
        void (^hide)(NSNotification *) = ^(__unused NSNotification *note) { NFBKeyboardSet(NO); };
        [center addObserverForName:UIKeyboardWillShowNotification object:nil queue:main usingBlock:show];
        [center addObserverForName:UIKeyboardDidShowNotification object:nil queue:main usingBlock:show];
        [center addObserverForName:UIKeyboardWillHideNotification object:nil queue:main usingBlock:hide];
        [center addObserverForName:UIKeyboardDidHideNotification object:nil queue:main usingBlock:hide];
        NFBDebugLog(@"keyboard: observers installed");
    });
}
