#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "NFBPrivate.h"
#import "NFBTrollBadgeText.h"
#import "NFBDebugLog.h"
#include <string.h>

// TrollOpen 1.5.2: these owners expose icon-button and bundle-ID collections.
// Only getters/setters are observed. No original gesture/action is replaced.
static NSHashTable *owners;
static NSHashTable<UILabel *> *labels;
static char badgeKey;
static id (*trayGet)(id, SEL);
static id (*panelGet)(id, SEL);
static void (*traySet)(id, SEL, id);
static void (*panelSet)(id, SEL, id);
static BOOL trayHooked, panelHooked;
static void remember(id owner) {
    if (NSThread.isMainThread) [owners addObject:owner];
    else dispatch_async(dispatch_get_main_queue(), ^{ [owners addObject:owner]; });
}
static id getTray(id self, SEL cmd) { remember(self); return trayGet(self, cmd); }
static id getPanel(id self, SEL cmd) { remember(self); return panelGet(self, cmd); }
static void setTray(id self, SEL cmd, id value) { traySet(self, cmd, value); remember(self); }
static void setPanel(id self, SEL cmd, id value) { panelSet(self, cmd, value); remember(self); }
static BOOL hookOwner(NSString *className, NSString *getter, NSString *setter,
                      IMP getImp, IMP *oldGet, IMP setImp, IMP *oldSet) {
    Class cls = NSClassFromString(className);
    if (!cls) return NO;
    SEL get = NSSelectorFromString(getter), set = NSSelectorFromString(setter);
    NSMethodSignature *g = [cls instanceMethodSignatureForSelector:get];
    NSMethodSignature *s = [cls instanceMethodSignatureForSelector:set];
    if (g.numberOfArguments != 2 || g.methodReturnType[0] != '@' ||
        s.numberOfArguments != 3 || s.methodReturnType[0] != 'v' ||
        [s getArgumentTypeAtIndex:2][0] != '@') return NO;
    MSHookMessageEx(cls, get, getImp, oldGet);
    MSHookMessageEx(cls, set, setImp, oldSet);
    NFBDebugLog(@"troll-badge: observing %@.%@", className, getter);
    return YES;
}
static id iconForID(NSString *app) {
    if (![app isKindOfClass:NSString.class] || !app.length) return nil;
    id model = NFBGet(NFBSingleton(@"SBIconController"), @"model");
    SEL sel = NSSelectorFromString(@"applicationIconForBundleIdentifier:");
    NSMethodSignature *sig = [model methodSignatureForSelector:sel];
    if (sig.numberOfArguments != 3 || sig.methodReturnType[0] != '@' ||
        [sig getArgumentTypeAtIndex:2][0] != '@') return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(model, sel, app);
}
static BOOL visible(UIView *button) {
    if (!button.window || CGRectIsEmpty(button.bounds)) return NO;
    for (UIView *view = button; view; view = view.superview)
        if (view.hidden || view.alpha < 0.01) return NO;
    return CGRectIntersectsRect([button convertRect:button.bounds toView:button.window], button.window.bounds);
}
static void updateButton(UIView *button, NSString *app) {
    if (![button isKindOfClass:UIControl.class] || !visible(button)) return;
    id value = NFBGet(iconForID(app), @"badgeNumberOrString");
    NSString *text = NFBTrollBadgeText(value);
    if (!text.length) return;
    UILabel *label = objc_getAssociatedObject(button, &badgeKey);
    if (!label) {
        label = [UILabel new];
        label.userInteractionEnabled = NO;
        label.isAccessibilityElement = NO;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = UIColor.systemRedColor;
        label.clipsToBounds = YES;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.45;
        objc_setAssociatedObject(button, &badgeKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [labels addObject:label];
    }
    if (label.superview != button) [button addSubview:label];
    CGFloat side = MIN(button.bounds.size.width, button.bounds.size.height);
    CGFloat height = MIN(20, MAX(10, side * 0.34));
    label.font = [UIFont boldSystemFontOfSize:height * 0.65];
    CGFloat width = MIN(MAX(height, [text sizeWithAttributes:@{NSFontAttributeName:label.font}].width + 8),
                        MAX(height, button.bounds.size.width - 2));
    // Keep the badge wholly inside the button so TrollOpen's tray clipping is safe.
    label.frame = CGRectMake(CGRectGetMaxX(button.bounds) - width - 1,
                             CGRectGetMinY(button.bounds) + 1, width, height);
    label.layer.cornerRadius = height / 2;
    label.text = text;
    label.hidden = NO;
    [button bringSubviewToFront:label];
}
static NSString *explicitID(UIView *button) {
    for (NSString *key in @[@"bundleID", @"bundleIdentifier", @"accessibilityIdentifier"]) {
        id app = NFBGet(button, key);
        if ([app isKindOfClass:NSString.class] && iconForID(app)) return app;
    }
    return nil;
}
static void updateOwner(id owner) {
    BOOL tray = [owner isKindOfClass:NSClassFromString(@"TOJBClass013")];
    id buttons = NFBGet(owner, tray ? @"trayIconButtons" : @"appButtons");
    id ids = NFBGet(owner, tray ? @"minimizedBundleIDs" : @"bundleIDs");
    if ([buttons isKindOfClass:NSDictionary.class]) {
        for (id app in buttons) updateButton(buttons[app], app);
        return;
    }
    if (![buttons isKindOfClass:NSArray.class]) return;
    // Prefer an explicit per-button ID. Use the owner's paired list only when
    // both lists are complete; never zip a partially rebuilt set of buttons.
    BOOL paired = [ids isKindOfClass:NSArray.class] && [ids count] == [buttons count];
    for (NSUInteger i = 0; i < [buttons count]; i++) {
        id button = buttons[i];
        if (![button isKindOfClass:UIControl.class]) continue;
        NSString *app = explicitID(button);
        if (!app && paired && [ids[i] isKindOfClass:NSString.class]) app = ids[i];
        if (app.length) updateButton(button, app);
    }
}
static void refreshBadges(void) {
    if (!trayHooked) trayHooked = hookOwner(@"TOJBClass013", @"trayIconButtons", @"setTrayIconButtons:",
        (IMP)getTray, (IMP *)&trayGet, (IMP)setTray, (IMP *)&traySet);
    if (!panelHooked) panelHooked = hookOwner(@"TOJBClass019", @"appButtons", @"setAppButtons:",
        (IMP)getPanel, (IMP *)&panelGet, (IMP)setPanel, (IMP *)&panelSet);
    // Hiding first clears zeroed badges and reused/removed buttons. Updates happen
    // synchronously on main, so there is no intervening rendered blank frame.
    for (UILabel *label in labels) label.hidden = YES;
    id enabled = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), CFSTR("local.notifybubbles")));
    if (enabled && ![enabled boolValue]) return;
    for (id owner in owners.allObjects) {
        @try { updateOwner(owner); }
        @catch (NSException *error) { NFBDebugLog(@"troll-badge: %@", error); }
    }
}
__attribute__((constructor)) static void installTrollBadges(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        owners = [NSHashTable weakObjectsHashTable];
        labels = [NSHashTable weakObjectsHashTable];
        refreshBadges();
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *t) { refreshBadges(); }];
        timer.tolerance = 0.1;
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    });
}
