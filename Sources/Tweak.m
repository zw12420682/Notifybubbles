#import "NFBManager.h"
#import "NFBPrivate.h"
#import <objc/runtime.h>
#import <substrate.h>
#include <string.h>

static void NFBMain(void (^block)(void)) {
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

// Observe system delivery after its notification policy decisions. Never suppress,
// alter, or replace the original method; system banners remain available.
static void NFBCapture(id destination, id request) {
    NFBMain(^{
        NSString *className = NSStringFromClass([destination class]).lowercaseString;
        NSString *identifier = NFBString(NFBGet(destination, @"identifier")).lowercaseString;
        BOOL banner = [className containsString:@"bannerdestination"] || [identifier containsString:@"banner"];
        BOOL lock = [className containsString:@"coversheet"] || [className containsString:@"listviewcontroller"] ||
            [identifier containsString:@"lockscreen"] || [identifier containsString:@"coversheet"];
        if (!banner && !lock) return;
        if (lock && !banner) {
            id manager = NFBSingleton(@"SBLockScreenManager");
            if (![manager respondsToSelector:@selector(isUILocked)] || ![manager isUILocked]) return;
            // Only include applications whose request is also eligible for banners.
            id destinations = NFBGet(request, @"requestDestinations");
            if (![destinations isKindOfClass:NSSet.class] && ![destinations isKindOfClass:NSArray.class]) return;
            BOOL hasBanner = NO;
            for (id item in destinations) {
                if ([NFBString(item).lowercaseString containsString:@"banner"]) { hasBanner = YES; break; }
            }
            if (!hasBanner) return;
        }
        [[NFBManager shared] receiveRequest:request destination:destination];
    });
}

static void (*originalPresent3)(id, SEL, id, id, BOOL);
static void replacedPresent3(id self, SEL cmd, id destination, id request, BOOL suppress) {
    originalPresent3(self, cmd, destination, request, suppress);
    if (!suppress) NFBCapture(destination, request);
}
static void (*originalPresent2)(id, SEL, id, id);
static void replacedPresent2(id self, SEL cmd, id destination, id request) {
    originalPresent2(self, cmd, destination, request);
    NFBCapture(destination, request);
}
static void (*originalBannerPost)(id, SEL, id, id);
static void replacedBannerPost(id self, SEL cmd, id request, id coalesced) {
    originalBannerPost(self, cmd, request, coalesced);
    NFBCapture(self, request);
}
// Keep collection independent of the tweak's lock-screen visibility setting.
// While locked, requests can go to the list instead of the banner presentation path.
static void (*originalPost)(id, SEL, id);
static void replacedPost(id self, SEL cmd, id request) {
    originalPost(self, cmd, request);
    NFBMain(^{
        id lock = NFBSingleton(@"SBLockScreenManager");
        if (![lock respondsToSelector:@selector(isUILocked)] || ![lock isUILocked]) return;
        id targets = NFBGet(request, @"requestDestinations");
        if (![targets isKindOfClass:NSSet.class] && ![targets isKindOfClass:NSArray.class]) return;
        BOOL bannerEligible = NO;
        for (id value in targets)
            if ([NFBString(value).lowercaseString containsString:@"banner"]) bannerEligible = YES;
        if (!bannerEligible) return;
        id wrapper = NFBGet(UIApplication.sharedApplication, @"notificationDispatcher");
        id destination = NFBGet(wrapper, @"bannerDestination");
        if (destination) [[NFBManager shared] receiveRequest:request destination:destination];
    });
}
static void (*originalWithdraw)(id, SEL, id);
static void replacedWithdraw(id self, SEL cmd, id request) {
    originalWithdraw(self, cmd, request);
    NFBMain(^{ [[NFBManager shared] withdrawRequest:request]; });
}
static void (*originalRemove)(id, SEL, id);
static void replacedRemove(id self, SEL cmd, id request) {
    originalRemove(self, cmd, request);
    NFBMain(^{ [[NFBManager shared] withdrawRequest:request]; });
}
static void (*originalRemoveSection)(id, SEL, id);
static void replacedRemoveSection(id self, SEL cmd, id section) {
    originalRemoveSection(self, cmd, section);
    NFBMain(^{ if (NFBString(section)) [[NFBManager shared] removeSection:section]; });
}

// Reject incompatible signatures instead of installing a hook with an unsafe ABI.
static BOOL NFBHook(Class cls, NSString *name, const char *arguments, IMP replacement, IMP *original) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(signature.methodReturnType, @encode(void)) || signature.numberOfArguments != strlen(arguments) + 2) return NO;
    for (NSUInteger index = 0; index < strlen(arguments); index++) {
        char actual = [signature getArgumentTypeAtIndex:index + 2][0];
        if (arguments[index] == 'B' && (actual == 'B' || actual == 'c')) continue;
        if (actual != arguments[index]) return NO;
    }
    MSHookMessageEx(cls, selector, replacement, original);
    return YES;
}
static void NFBPreferencesChanged(CFNotificationCenterRef center, void *observer,
    CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)object; (void)info;
    BOOL clear = CFEqual(name, CFSTR("local.notifybubbles/clear"));
    NFBMain(^{
        if (clear) [[NFBManager shared] clear];
        else [[NFBManager shared] reloadPreferences];
    });
}
static void NFBInstall(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class dispatcher = NSClassFromString(@"NCNotificationDispatcher");
    if (!dispatcher) return;
    installed = YES;
    BOOL feed = NFBHook(dispatcher, @"destination:willPresentNotificationRequest:suppressAlerts:", "@@B",
        (IMP)replacedPresent3, (IMP *)&originalPresent3);
    if (!feed) feed = NFBHook(dispatcher, @"destination:willPresentNotificationRequest:", "@@",
        (IMP)replacedPresent2, (IMP *)&originalPresent2);
    if (!feed) feed = NFBHook(NSClassFromString(@"SBNotificationBannerDestination"),
        @"postNotificationRequest:forCoalescedNotification:", "@@", (IMP)replacedBannerPost, (IMP *)&originalBannerPost);
    BOOL withdraw = NFBHook(dispatcher, @"withdrawNotificationWithRequest:", "@", (IMP)replacedWithdraw, (IMP *)&originalWithdraw);
    BOOL collection = NFBHook(dispatcher, @"postNotificationWithRequest:", "@", (IMP)replacedPost, (IMP *)&originalPost);
    BOOL remove = NFBHook(dispatcher, @"_didRemoveNotificationRequest:", "@", (IMP)replacedRemove, (IMP *)&originalRemove);
    NFBHook(dispatcher, @"removeNotificationSectionWithIdentifier:", "@", (IMP)replacedRemoveSection, (IMP *)&originalRemoveSection);
    NSLog(@"[NotifyBubbles] 0.29.0 feed=%d collection=%d withdraw=%d remove=%d; first-device validation required", feed, collection, withdraw, remove);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        NFBPreferencesChanged, CFSTR("local.notifybubbles/preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        NFBPreferencesChanged, CFSTR("local.notifybubbles/clear"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    [[NFBManager shared] reloadPreferences];
}
__attribute__((constructor)) static void NFBStart(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ NFBInstall(); });
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { NFBInstall(); }];
}
