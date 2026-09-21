#import "NFBManager.h"
#import "NFBPrivate.h"
#import "NFBStore.h"
#import "NFBGeometry.h"
#import "NFBStorageLayout.h"
#import "NFBSwitcher.h"
#import "NFBTrollOpen.h"
#import "NFBNotificationPolicy.h"
#import "NFBAppExit.h"
#import "NFBKeyboard.h"
#import "NFBDebugLog.h"
#import "NFBEdgeInspection.h"

static const NSTimeInterval NFBMotion = 0.6;
// How long a bubble stays expanded after an unread arrives.
static const NSTimeInterval NFBHold = 1.0;
// Double-tap is intentionally inert, so a single tap no longer has to wait for a
// possible second tap: the recognizer fires on touch-up with no arbitration lag.
// This guard only swallows the accidental repeat that follows a real double tap.
static const NSTimeInterval NFBGestureCooldown = 0.25;
// While an app sits in the split view its bubble stays fully opaque (alpha 1.0,
// independent of the user's opacity slider) and every other bubble drops to this
// fraction, so the split-view app reads as the active one without being pulled
// to the top of the row.
static const CGFloat NFBFloatingDim = 0.3;
// Vertical position (0 = top, 1 = bottom) the whole row shifts to while an app
// is in the split view, so it clears the floating window. Restores on exit.
static const CGFloat NFBFloatingPosition = 0.80;
// Vertical position the row shifts to while the keyboard is up, so the bubbles
// clear the keyboard. Applies in BOTH split view and fullscreen, and outranks
// every other position rule.
static const CGFloat NFBKeyboardPosition = 0.49;
// How long the folded (no-unread) bubbles stay spread out after a tap on the
// stack edge, before folding back into a thin stack.
static const NSTimeInterval NFBStackHold = 20.0;
// Synthetic bubble id that rides at the top of the row while an app is in the
// split view. Tapping it clears every background app at once. It never enters
// the store or the switcher ordering.
static NSString * const NFBStorageID = @"__notifybubbles.storage__";
static NSString * const NFBClearAllID = @"__notifybubbles.clearall__";
#import <QuartzCore/QuartzCore.h>

static CFStringRef const NFBDomain = CFSTR("local.notifybubbles");
static BOOL NFBPreference(NSString *key, BOOL fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NFBDomain));
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static double NFBNumber(NSString *key, double fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NFBDomain));
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

// The transparent strip must not block touches beside a half-hidden bubble.
@interface NFBRail : UIScrollView
@end
@implementation NFBRail
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (point.y < CGRectGetMinY(self.bounds) || point.y > CGRectGetMaxY(self.bounds)) return NO;
    for (UIView *view in self.subviews) {
        if (![view isKindOfClass:UIControl.class] || !view.userInteractionEnabled) continue;
        if ([view pointInside:[view convertPoint:point fromView:self] withEvent:event]) return YES;
    }
    return NO;
}
@end

@interface NFBWindow : UIWindow
@end
@implementation NFBWindow
- (BOOL)_canShowWhileLocked { return YES; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

@interface NFBBubble : UIControl
@property(nonatomic, copy) NSString *appID;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) UILabel *badge;
@property(nonatomic) BOOL opening;
@end
@implementation NFBBubble
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.isAccessibilityElement = YES;
        _imageView = [[UIImageView alloc] initWithFrame:CGRectMake(7, 7, 48, 48)];
        _imageView.layer.cornerRadius = 24;
        _imageView.clipsToBounds = YES;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        [self addSubview:_imageView];
        _badge = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 22, 20)];
        _badge.backgroundColor = UIColor.systemRedColor;
        _badge.textColor = UIColor.whiteColor;
        _badge.font = [UIFont boldSystemFontOfSize:12];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 10;
        _badge.clipsToBounds = YES;
        [self addSubview:_badge];
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.22;
        self.layer.shadowRadius = 5;
        self.layer.shadowOffset = CGSizeMake(0, 2);
    }
    return self;
}
@end

@interface NFBManager ()
@property(nonatomic, strong) NFBStore *store;
@property(nonatomic, strong) NFBWindow *window;
@property(nonatomic, strong) UIScrollView *rail;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *buttons;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *expandedUntil;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *icons;
@property(nonatomic, strong) NSMutableSet<NSString *> *burstApps;
@property(nonatomic, strong) NSArray<NSString *> *lastSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *dismissedSwitcher;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *generations;
@property(nonatomic, strong) NSMutableSet<NSString *> *needsReveal;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastBadges;
@property(nonatomic, strong) NFBRecord *pendingRecord;
@property(nonatomic) NSTimeInterval pendingUntil;
@property(nonatomic) NSUInteger emptyReads;
@property(nonatomic) CGFloat verticalPosition;
@property(nonatomic, copy) NSString *lastActiveApp;
@property(nonatomic, copy) NSArray *lastLayoutApps;
@property(nonatomic) CGFloat iconSize;
@property(nonatomic) CGFloat iconOpacity;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL showLock;
@property(nonatomic) BOOL showHome;
@property(nonatomic) BOOL showApps;
@property(nonatomic) NSTimeInterval lastGestureAt;
// Until when the folded (no-unread) bubbles stay spread out after a tap. When
// in the past, they fold back into a thin stack at the bottom edge.
@property(nonatomic) NSTimeInterval stackUntil;
// Apps whose bubble is already retracting because we asked TrollOpen to end the
// floating window. Marking them lets the retract animation start on the same
// frame as the window transition instead of waiting for the window to be gone.
@property(nonatomic, strong) NSMutableSet<NSString *> *retracting;
// High-frequency watcher that only runs while a floating window exists, so a
// window dismissed outside the plugin (TrollOpen's own bar, app crash, exit) is
// picked up in ~one frame rather than on the next 0.5s poll.
@property(nonatomic, strong) NSTimer *floatingWatch;
@property(nonatomic, copy) NSString *watchedFloating;
// Previous keyboard state, so refresh can spot the up/down edges.
@property(nonatomic) BOOL keyboardUp;
// Bubbles that were out when the keyboard rose; restored when it falls.
@property(nonatomic, strong) NSMutableSet<NSString *> *keyboardSuspended;
// Apps whose bubble is mid-shake (a new message arrived while an app sits in
// the split view). Kept full opacity for the shake's duration.
@property(nonatomic, strong) NSMutableSet<NSString *> *shakingApps;
- (void)refresh;
- (void)beginRetracting:(NSString *)app;
- (void)syncFloatingWatch:(NSString *)floating;
- (void)floatingWatchFired;
- (BOOL)isFloatingBubble:(NFBBubble *)button;
- (BOOL)acceptGesture;
- (void)burstBubble:(NFBBubble *)button;
- (BOOL)executeRecord:(NFBRecord *)record;
- (void)tick;
- (void)startTimer;
- (void)extendApp:(NSString *)app;
- (void)closeAppsInOrder:(NSArray<NSString *> *)apps;
- (void)openApp:(NSString *)app;
- (void)showOpenNotice:(NSString *)message;
- (BOOL)isLocked;
- (void)clearBackground;
- (void)clearAllTapped:(UITapGestureRecognizer *)gesture;
- (void)styleClearAllButton:(NFBBubble *)button;
- (void)styleStorageButton:(NFBBubble *)button count:(NSUInteger)count;
- (void)shakeBubble:(NFBBubble *)button;
@end

@implementation NFBManager
+ (instancetype)shared {
    static NFBManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [self new]; });
    return manager;
}
- (instancetype)init {
    if ((self = [super init])) {
        _store = [NFBStore new];
        _buttons = [NSMutableDictionary dictionary];
        _expandedUntil = [NSMutableDictionary dictionary];
        _icons = [NSMutableDictionary dictionary];
        _burstApps = [NSMutableSet set];
        _retracting = [NSMutableSet set];
        _dismissedSwitcher = [NSMutableSet set];
        _generations = [NSMutableDictionary dictionary];
        _needsReveal = [NSMutableSet set];
        _lastBadges = [NSMutableDictionary dictionary];
        _keyboardSuspended = [NSMutableSet set];
        _shakingApps = [NSMutableSet set];
        __weak NFBManager *weakSelf = self;
        NFBKeyboardInstall(^{ [weakSelf refresh]; });
        [self reloadPreferences];
    }
    return self;
}
- (void)reloadPreferences {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    CFPreferencesAppSynchronize(NFBDomain);
    self.verticalPosition = NFBPosition(NFBNumber(@"VerticalPosition", 0.7));
    self.iconSize = NFBSize(NFBNumber(@"IconSize", 48));
    self.iconOpacity = NFBOpacity(NFBNumber(@"IconOpacity", 1));
    self.enabled = NFBPreference(@"Enabled", YES);
    self.showLock = NFBPreference(@"ShowOnLock", YES);
    self.showHome = NFBPreference(@"ShowOnHome", YES);
    self.showApps = NFBPreference(@"ShowInApps", YES);
    if (!self.enabled) {
        [self.timer invalidate]; self.timer = nil; [self clear];
    } else { [self startTimer]; [self tick]; }
}
- (void)receiveRequest:(id)request destination:(id)destination {
    if (!self.enabled) return;
    NSString *appID = NFBString(NFBGet(request, @"sectionIdentifier"));
    NSString *notificationID = NFBString(NFBGet(request, @"notificationIdentifier"));
    if (!appID.length || !notificationID.length || !NFBGet(request, @"defaultAction")) return;
    if (![self.store putApp:appID notification:notificationID request:request destination:destination]) return;
    self.generations[appID] = @([self.generations[appID] unsignedIntegerValue] + 1);
    [self.dismissedSwitcher removeObject:appID];
    id image = NFBGet(NFBGet(request, @"content"), @"icon");
    if ([image isKindOfClass:UIImage.class]) self.icons[appID] = image;
    if ([self shouldShow]) [self extendApp:appID];
    else [self.needsReveal addObject:appID];
    [self startTimer];
    [self refresh];
    NFBBubble *updated = self.buttons[appID];
    if (!self.window.hidden && updated) {
        // New message while an app sits in the split view: shake that bubble as
        // a reminder and keep it highlighted, since it is otherwise dimmed.
        if (NFBTrollVisibleApp().length > 0 && ![appID isEqualToString:NFBClearAllID]) {
            [self shakeBubble:updated];
        }
        CGRect row = CGRectMake(0, updated.center.y - updated.bounds.size.height / 2, self.rail.bounds.size.width, updated.bounds.size.height);
        [self.rail scrollRectToVisible:row animated:!UIAccessibilityIsReduceMotionEnabled()];
    }
}
- (void)withdrawRequest:(id)request {
    NSString *appID = NFBString(NFBGet(request, @"sectionIdentifier"));
    NSString *notificationID = NFBString(NFBGet(request, @"notificationIdentifier"));
    if (appID && notificationID) [self.store removeApp:appID notification:notificationID];
    [self refresh];
}
- (void)removeSection:(NSString *)section {
    [self.store removeApp:section]; [self refresh];
}
- (NSArray<NSString *> *)orderedAppsForRemoval {
    NSMutableOrderedSet *apps = [NSMutableOrderedSet orderedSetWithArray:self.lastLayoutApps ?: @[]];
    [apps addObjectsFromArray:self.store.appIDs];
    [apps removeObject:NFBClearAllID];
    [apps removeObject:NFBStorageID];
    return apps.array;
}
- (void)clear {
    [self.dismissedSwitcher addObjectsFromArray:self.lastSwitcher ?: @[]];
    [self closeAppsInOrder:[self orderedAppsForRemoval]];
}
// "一键清理后台": terminate every app in the switcher/row except the one still
// occupying the floating window, mirroring the long-press exit path but for the
// whole background at once.
- (void)clearBackground {
    NSString *floating = NFBTrollVisibleApp();
    NSMutableArray<NSString *> *targets = [NSMutableArray array];
    for (NSString *app in [self orderedAppsForRemoval]) {
        if ([app isEqualToString:floating]) continue;
        [targets addObject:app];
    }
    if (!targets.count) return;
    NFBDebugLog(@"gesture: clear-background -> %lu apps", (unsigned long)targets.count);
    [self.dismissedSwitcher addObjectsFromArray:targets];
    [self closeAppsInOrder:targets];
    [targets enumerateObjectsUsingBlock:^(NSString *app, NSUInteger index, __unused BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.35 + index * 0.16) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NFBTerminateApp(app);
            [self refresh];
        });
    }];
}
- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    if (self.buttons[button.appID] != button) return;
    if (![self acceptGesture]) return;
    [self clearBackground];
}
// Give the clear-all bubble a distinct look: a red-tinted trash glyph, no badge,
// and an accessibility label so VoiceOver reads it as an action, not an app.
- (void)styleClearAllButton:(NFBBubble *)button {
    button.badge.hidden = YES;
    button.imageView.contentMode = UIViewContentModeCenter;
    button.imageView.image = [UIImage systemImageNamed:@"trash.fill"];
    button.imageView.tintColor = UIColor.systemRedColor;
    button.imageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.accessibilityLabel = @"一键清理后台";
    button.accessibilityHint = @"点击终止所有后台应用";
}
// Reminder for a fresh notification while an app sits in the split view: a
// 2-second decaying horizontal shake plus a temporary full-opacity highlight,
// then the bubble settles back to whatever opacity the split-view layout assigns
// it. The button's transform is identity here (split view keeps every bubble
// expanded), so a layer translation never fights the retraction offset.
- (void)shakeBubble:(NFBBubble *)button {
    if (!button || !button.superview) return;
    NSString *appID = button.appID;
    [self.shakingApps addObject:appID];
    [button.layer removeAnimationForKey:@"NFBShake"];
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.duration = 2.0;
        shake.values = @[@0, @(-8), @8, @(-7), @7, @(-6), @6, @(-5), @5, @(-4), @4, @(-3), @3, @(-2), @2, @0];
        shake.keyTimes = @[@0, @(1.0/15), @(2.0/15), @(3.0/15), @(4.0/15), @(5.0/15), @(6.0/15), @(7.0/15),
                           @(8.0/15), @(9.0/15), @(10.0/15), @(11.0/15), @(12.0/15), @(13.0/15), @(14.0/15), @1.0];
        shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        shake.removedOnCompletion = YES;
        [button.layer addAnimation:shake forKey:@"NFBShake"];
    }
    [UIView animateWithDuration:0.15 animations:^{ button.alpha = 1.0; } completion:nil];
    __weak NFBManager *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.shakingApps removeObject:appID];
        [weakSelf refresh];
    });
}
- (BOOL)isLocked {
    id lock = NFBSingleton(@"SBLockScreenManager");
    return ![lock respondsToSelector:@selector(isUILocked)] || [lock isUILocked];
}
- (void)startTimer {
    if (self.timer || !self.enabled) return;
    __weak NFBManager *weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *t) { [weakSelf tick]; }];
    self.timer.tolerance = 0.1;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
// Start the bubble's retract animation now, on the same frame the window
// transition begins. Previously the bubble waited for TrollOpen to report the
// window gone, so it only started moving after the window had finished closing.
- (void)beginRetracting:(NSString *)app {
    if (!app.length) return;
    [self.retracting addObject:app];
    // Drop any active reveal window too: a tap always extends the bubble first,
    // and that leftover timer would otherwise force it straight back out.
    [self.expandedUntil removeObjectForKey:app];
    [self.needsReveal removeObject:app];
    [self refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.retracting removeObject:app];
        [self refresh]; // Adopt whichever state TrollOpen actually settled into.
    });
}
// Poll the floating window only while one exists, so a window dismissed outside
// the plugin (TrollOpen's own bar, app exit, crash) is reflected in about one
// frame rather than on the next 0.5s poll — with no fast timer the rest of the time.
- (void)syncFloatingWatch:(NSString *)floating {
    BOOL needed = self.enabled && floating.length > 0;
    if (!needed) {
        if (self.floatingWatch) { [self.floatingWatch invalidate]; self.floatingWatch = nil; }
        self.watchedFloating = nil;
        return;
    }
    if (self.floatingWatch) return;
    self.watchedFloating = floating;
    __weak NFBManager *weakSelf = self;
    self.floatingWatch = [NSTimer timerWithTimeInterval:0.05 repeats:YES
        block:^(__unused NSTimer *t) { [weakSelf floatingWatchFired]; }];
    self.floatingWatch.tolerance = 0.015;
    [NSRunLoop.mainRunLoop addTimer:self.floatingWatch forMode:NSRunLoopCommonModes];
}
- (void)floatingWatchFired {
    NSString *now = NFBTrollVisibleApp();
    if (now == self.watchedFloating || [now isEqualToString:self.watchedFloating]) return;
    self.watchedFloating = now;
    [self refresh];
}
- (void)extendApp:(NSString *)app {
    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0 : NFBMotion;
    NSNumber *until = @(CACurrentMediaTime() + duration + NFBHold);
    self.expandedUntil[app] = until;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + NFBHold) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.expandedUntil[app] isEqual:until]) [self refresh];
    });
}
- (void)tick {
    if (!self.enabled) return;
    if (self.pendingRecord) {
        NSString *front = NFBString(NFBGet(NFBGet(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication"), @"bundleIdentifier"));
        if (![self isLocked] && [front isEqual:self.pendingRecord.appID]) {
            [self.store consumeRecord:self.pendingRecord]; self.pendingRecord = nil;
        } else if (CACurrentMediaTime() > self.pendingUntil) self.pendingRecord = nil;
    }
    // Do not interpret a temporarily inaccessible switcher on the lock screen as empty.
    if (![self isLocked]) {
        NSArray *current = NFBReadSwitcherApps();
        if (current) {
            NSSet *set = [NSSet setWithArray:current];
            [self.dismissedSwitcher intersectSet:set];
            if (current.count == 0 && self.lastSwitcher.count > 0) {
                // Require two consecutive empty reads to reject intermediate snapshots.
                if (++self.emptyReads >= 2) {
                    [self closeAppsInOrder:[self orderedAppsForRemoval]];
                    self.lastSwitcher = current; self.emptyReads = 0;
                }
            } else {
                self.emptyReads = 0;
                NSSet *oldSet = [NSSet setWithArray:self.lastSwitcher ?: @[]];
                NSMutableArray *removed = [NSMutableArray array];
                for (NSString *app in self.store.appIDs)
                    if ([oldSet containsObject:app] && ![set containsObject:app]) [removed addObject:app];
                if (removed.count) [self closeAppsInOrder:removed];
                for (NSString *app in current) {
                    if (![oldSet containsObject:app])
                        self.generations[app] = @([self.generations[app] unsignedIntegerValue] + 1);
                    if (![self.dismissedSwitcher containsObject:app] && ![self.store.appIDs containsObject:app]) {
                        [self.store pinApp:app];
                        self.generations[app] = @([self.generations[app] unsignedIntegerValue] + 1);
                    }
                }
                self.lastSwitcher = current;
            }
        }
    }
    [self refresh];
}
- (void)closeAppsInOrder:(NSArray<NSString *> *)apps {
    NSDictionary *versions = [self.generations copy];
    [apps enumerateObjectsUsingBlock:^(NSString *app, NSUInteger index, __unused BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(index * 0.16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // A notification or reopened switcher card received after this snapshot survives.
            if (![self.generations[app] isEqual:versions[app]]) return;
            [self.burstApps addObject:app];
            [self.store closeApp:app]; [self.needsReveal removeObject:app];
            if ([self.pendingRecord.appID isEqual:app]) self.pendingRecord = nil;
            [self refresh];
        });
    }];
}
- (BOOL)shouldShow {
    id lock = NFBSingleton(@"SBLockScreenManager");
    // An unknown lock state must not display an interactive overlay.
    if (![lock respondsToSelector:@selector(isUILocked)]) return NO;
    if ([lock isUILocked]) return self.showLock;
    id springboard = UIApplication.sharedApplication;
    if (![springboard respondsToSelector:@selector(isShowingHomescreen)]) return NO;
    return [springboard isShowingHomescreen] ? self.showHome : self.showApps;
}
- (void)ensureWindow {
    if (self.window) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate; break;
        }
    }
    self.window = scene ? [[NFBWindow alloc] initWithWindowScene:scene] :
        [[NFBWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.clearColor;
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.rail = [NFBRail new];
    self.rail.clipsToBounds = YES;
    self.rail.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.window.clipsToBounds = YES;
    self.rail.backgroundColor = UIColor.clearColor;
    self.rail.showsVerticalScrollIndicator = NO;
    self.rail.alwaysBounceVertical = NO;
    [self.window.rootViewController.view addSubview:self.rail];
    // Never take the key window; keyboard and app focus belong to the system.
}
- (id)iconForApp:(NSString *)appID {
    id model = NFBGet(NFBSingleton(@"SBIconController"), @"model");
    if (![model respondsToSelector:@selector(applicationIconForBundleIdentifier:)]) return nil;
    @try { return [model applicationIconForBundleIdentifier:appID]; }
    @catch (__unused NSException *error) { return nil; }
}
- (void)updateBubble:(NFBBubble *)button record:(NFBRecord *)record {
    id icon = [self iconForApp:button.appID];
    // The badge reflects this app's unread count in our own store, not the
    // system icon's badge number. That keeps the badge visible for every app
    // with a pending notification (including in split view) and lets it clear
    // the moment the record is consumed — i.e. when the app is opened.
    NSUInteger unread = [self.store countForApp:button.appID];
    NSString *text = unread > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)unread] : nil;
    button.badge.hidden = !text.length;
    button.badge.text = text;
    CGFloat width = MAX(20, [text sizeWithAttributes:@{NSFontAttributeName:button.badge.font}].width + 10);
    button.badge.frame = CGRectMake(0, 0, width, 20);
    NSString *name = NFBString(NFBGet(icon, @"displayName")) ?: button.appID;
    button.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", name, text ?: (record ? @"有通知" : @"暂无新通知")];
    button.accessibilityHint = @"点击打开通知，无通知时通过 TrollOpen 分屏打开，长按关闭图标";
    // Secondary cleanup: when the system icon's own badge drops to zero (the app
    // was opened and cleared it) but no withdraw reached us, drop this app's
    // records so the store-count badge above also clears on the next refresh.
    id systemBadge = NFBGet(icon, @"badgeNumberOrString");
    BOOL systemCleared = NO;
    if ([systemBadge isKindOfClass:NSNumber.class]) systemCleared = [systemBadge longLongValue] <= 0;
    else if ([systemBadge isKindOfClass:NSString.class]) systemCleared = ![systemBadge length] || [systemBadge isEqualToString:@"0"];
    NSNumber *previous = self.lastBadges[button.appID];
    if (previous.doubleValue > 0 && systemCleared) [self.store removeApp:button.appID];
    if ([systemBadge isKindOfClass:NSNumber.class]) self.lastBadges[button.appID] = systemBadge;
    else if (systemCleared) self.lastBadges[button.appID] = @0;
    id image = self.icons[button.appID];
    if (!image) {
        SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if ([UIImage respondsToSelector:sel]) {
            @try { image = ((id (*)(id, SEL, id, int, CGFloat))objc_msgSend)(UIImage.class, sel, button.appID, 2, UIScreen.mainScreen.scale); }
            @catch (__unused NSException *error) {}
        }
        if ([image isKindOfClass:UIImage.class]) self.icons[button.appID] = image;
    }
    button.imageView.image = [image isKindOfClass:UIImage.class] ? image : [UIImage systemImageNamed:@"bell.fill"];
}
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    // A dismissed app (long-press exit or one-click clear) is only marked
    // "dismissed" so its bubble doesn't instantly reappear while the process is
    // still being torn down — iOS keeps a stale switcher card for a killed app,
    // so the switcher never reports it gone and the marker would linger forever.
    // If that app is now genuinely active again (frontmost, or the TrollOpen
    // floating app), it was deliberately re-opened: drop the marker and re-pin it
    // so its bubble returns right away instead of staying hidden until the user
    // manually swipes the stale card away and reopens a second time.
    NSString *reopened = NFBTrollVisibleApp();
    if (!reopened.length) {
        id springboard = UIApplication.sharedApplication;
        BOOL atHome = [springboard respondsToSelector:@selector(isShowingHomescreen)] && [springboard isShowingHomescreen];
        if (!atHome) reopened = NFBString(NFBGet(NFBGet(springboard, @"_accessibilityFrontMostApplication"), @"bundleIdentifier"));
    }
    if (reopened.length && [self.dismissedSwitcher containsObject:reopened]) {
        NFBDebugLog(@"refresh: dismissed app %@ reopened -> re-pin", reopened);
        [self.dismissedSwitcher removeObject:reopened];
        if (![self.store.appIDs containsObject:reopened]) [self.store pinApp:reopened];
    }
    NSMutableArray<NSString *> *apps = [NSMutableArray array];
    for (NSString *app in self.store.appIDs) {
        BOOL fromSwitcher = [self.lastSwitcher containsObject:app];
        BOOL notificationsAllowed = NFBSystemNotificationsAllowed(app, ^{ [self refresh]; });
        if (fromSwitcher || notificationsAllowed) [apps addObject:app];
    }
    NSString *floatingApp = NFBTrollVisibleApp();
    // Keep the fast watcher in step with reality every time we recompute layout.
    [self syncFloatingWatch:floatingApp];
    // A keyboard outranks everything else: typing is the one moment the bubbles
    // must be out of the way, so it pulls them all back in no matter what. The
    // ones it pulled in are remembered and popped back out the moment typing
    // ends (split-view bubbles come back on their own via floatingApp below).
    BOOL keyboardUp = NFBKeyboardVisible();
    if (keyboardUp != self.keyboardUp) {
        if (keyboardUp) {
            // Keyboard just rose: snapshot every bubble still riding its unread
            // timer, so it can be restored instead of silently expiring while
            // the user is typing.
            [self.keyboardSuspended removeAllObjects];
            for (NSString *app in self.store.appIDs) {
                if ([self.expandedUntil[app] doubleValue] > CACurrentMediaTime()) {
                    [self.keyboardSuspended addObject:app];
                }
            }
        } else {
            // Keyboard just fell: re-pop the bubbles it pulled in.
            for (NSString *app in [self.keyboardSuspended copy]) {
                if (![self.retracting containsObject:app] && [self.store.appIDs containsObject:app]) [self extendApp:app];
            }
            [self.keyboardSuspended removeAllObjects];
        }
        self.keyboardUp = keyboardUp;
    }
    id springboard = UIApplication.sharedApplication;
    BOOL home = [springboard respondsToSelector:@selector(isShowingHomescreen)] && [springboard isShowingHomescreen];
    NSString *active = floatingApp ?: (home ? nil : NFBString(NFBGet(NFBGet(springboard, @"_accessibilityFrontMostApplication"), @"bundleIdentifier")));
    // The split-view app keeps its position and is highlighted by opacity instead
    // of being pulled to the top, so only the plain frontmost app gets promoted.
    if (!floatingApp.length && active.length && [apps containsObject:active]) {
        [apps removeObject:active]; [apps insertObject:active atIndex:0];
        if (![self.lastActiveApp isEqual:active]) [self.store promoteApp:active];
    }
    self.lastActiveApp = active;
    if (floatingApp.length) NFBInspectTrollEdges();
    // While an app is in the split view, a synthetic "clear background" bubble
    // rides at the very top of the row. It is layout-only: never in the store,
    // never promoted, and dropped the moment the split view closes.
    NSMutableArray<NSString *> *displayApps = [apps mutableCopy];
    if (floatingApp.length > 0) [displayApps addObject:NFBClearAllID];
    BOOL stackOpen = self.stackUntil > CACurrentMediaTime();
    NSUInteger storedCount = 0;
    if (!floatingApp.length && !stackOpen) {
        displayApps = NFBFoldedRows(apps, NFBStorageID, ^NSUInteger(NSString *app) {
            return [self.store countForApp:app];
        }, &storedCount);
    }
    BOOL orderChanged = ![self.lastLayoutApps isEqualToArray:displayApps];
    self.lastLayoutApps = [displayApps copy];
    for (NSString *appID in self.buttons.allKeys) {
        if ([displayApps containsObject:appID]) continue;
        NFBBubble *button = self.buttons[appID];
        [self.buttons removeObjectForKey:appID];
        [self.expandedUntil removeObjectForKey:appID];
        button.userInteractionEnabled = NO;
        [self.icons removeObjectForKey:appID];
        if ([self.burstApps containsObject:appID]) {
            [self.burstApps removeObject:appID];
            [self burstBubble:button];
            continue;
        }
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
            button.alpha = 0; button.transform = CGAffineTransformMakeTranslation(self.iconSize + 20, 0);
        } completion:^(__unused BOOL done) { [button removeFromSuperview]; }];
    }
    if (!apps.count || !self.enabled) {
        // Delay hiding until the removal animation completes; recheck new arrivals.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.enabled || !self.buttons.count) self.window.hidden = YES;
        });
        return;
    }
    if (![self shouldShow]) { self.window.hidden = YES; return; }
    [self ensureWindow];
    self.window.hidden = NO;
    for (NSString *app in [self.needsReveal copy]) {
        // An open keyboard outranks even a fresh notification: leave the reveal
        // pending instead of burning it, so it shows the moment typing ends.
        if (keyboardUp) break;
        if ([self.store.appIDs containsObject:app]) [self extendApp:app];
        [self.needsReveal removeObject:app];
    }
    UIView *root = self.window.rootViewController.view;
    CGRect bounds = root.bounds;
    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat top = MAX(safe.top, 48) + 30;
    CGFloat diameter = self.iconSize;
    CGFloat side = diameter + 14;
    CGFloat step = storedCount ? diameter + 8 : side + 4;
    CGFloat available = MAX(side, bounds.size.height - top - MAX(safe.bottom, 20) - 20);
    CGFloat height = MIN(available, displayApps.count * step);
    // Keyboard outranks every other rule (typing must never be covered): the row
    // shifts to NFBKeyboardPosition in both split view and fullscreen. Otherwise,
    // while an app is in the split view the row shifts down to clear the floating
    // window (NFBFloatingPosition), then returns to the user's slider setting.
    CGFloat position = keyboardUp ? NFBKeyboardPosition : (floatingApp.length > 0 ? NFBFloatingPosition : self.verticalPosition);
    // Anchor the FIRST bubble (index 0, the lowest one) to a fixed screen Y so it
    // never moves: each new bubble stacks upward on top of it. The first bubble's
    // center sits (step - side/2) above the rail's bottom edge, so fixing the
    // rail's bottom edge fixes the first bubble. Anchoring the top edge instead
    // would make the row grow both up and down as bubbles arrive (spreading from
    // the middle), which is not what we want.
    CGFloat anchor = top + available * position;
    // Use the actual screen edge, not safeArea.right, for exactly half exposure.
    CGRect railFrame = CGRectMake(bounds.size.width - side, anchor + (step - side/2) - height, side, height);
    if (!CGRectEqualToRect(self.rail.frame, railFrame)) {
        if (CGRectIsEmpty(self.rail.frame)) self.rail.frame = railFrame;
        else [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : NFBMotion delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
            animations:^{ self.rail.frame = railFrame; } completion:nil];
    }
    self.rail.contentSize = CGSizeMake(side, displayApps.count * step);
    CGFloat maxOffset = MAX(0, self.rail.contentSize.height - height);
    if (orderChanged || self.rail.contentOffset.y > maxOffset) self.rail.contentOffset = CGPointMake(0, maxOffset);
    [displayApps enumerateObjectsUsingBlock:^(NSString *appID, NSUInteger index, __unused BOOL *stop) {
        BOOL isClearAll = [appID isEqualToString:NFBClearAllID];
        BOOL isStorage = [appID isEqualToString:NFBStorageID];
        NFBBubble *button = self.buttons[appID];
        BOOL fresh = !button;
        if (fresh) {
            button = [[NFBBubble alloc] initWithFrame:CGRectZero];
            button.appID = appID;
            if (isStorage) {
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(storageTapped:)];
                [button addGestureRecognizer:tap];
            } else if (isClearAll) {
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearAllTapped:)];
                tap.numberOfTapsRequired = 1;
                [button addGestureRecognizer:tap];
            } else {
                // Double tap is intentionally not installed. Removing it lets the tap
                // recognizer resolve on touch-up instead of waiting out the multi-tap
                // window, which is what made the old single tap feel half a beat late.
                UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapped:)];
                singleTap.numberOfTapsRequired = 1;
                [button addGestureRecognizer:singleTap];
                UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
                hold.minimumPressDuration = 0.45;
                // Cancel the tap once a hold is recognised, so exit never fires twice.
                hold.cancelsTouchesInView = YES;
                [button addGestureRecognizer:hold];
            }
            self.buttons[appID] = button;
            [self.rail addSubview:button];
        }
        if (isStorage) [self styleStorageButton:button count:storedCount];
        else if (isClearAll) [self styleClearAllButton:button];
        else [self updateBubble:button record:[self.store latestForApp:appID]];
        // A bubble we already started retracting must not be re-expanded by the
        // stale "window still visible" reading taken mid-transition.
        BOOL retracting = [self.retracting containsObject:appID];
        // "Has unread" is now the store's unread count, not a short timer: a
        // bubble with any pending notification stays fully visible (never folds)
        // until the record is consumed by opening the app.
        BOOL hasUnread = [self.store countForApp:appID] > 0;
        // With an app sitting in the TrollOpen split view every bubble stays out
        // instead of only that app's, so the whole row is reachable at a glance.
        // Outside split view, bubbles with no unread fold into a stack unless the
        // stack is currently spread open (stackOpen).
        BOOL expanded = !keyboardUp && !retracting && (floatingApp.length > 0 || hasUnread || stackOpen);
        CGFloat retraction = (isStorage && !keyboardUp) ? 0 : (expanded ? 0 : NFBRetraction(diameter));
        CGAffineTransform target = CGAffineTransformMakeTranslation(retraction, 0);
        CGRect targetBounds = CGRectMake(0, 0, side, side);
        CGFloat rowY = NFBRowCenter(displayApps.count, index, step, side);
        CGPoint targetCenter = CGPointMake(side / 2, rowY);
        if (fresh) {
            button.bounds = targetBounds;
            button.center = targetCenter;
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = isStorage ? diameter * 0.32 : diameter / 2;
            button.transform = CGAffineTransformMakeTranslation(side + 10, 0);
            button.alpha = 0;
        }
        // The clear-all bubble is an action, not an app: keep it fully opaque so
        // it stays discoverable, unlike the dimmed background bubbles around it.
        CGFloat alpha = self.iconOpacity;
        if (isClearAll) {
            alpha = 1.0;
        } else if (floatingApp.length > 0) {
            if ([floatingApp isEqualToString:appID]) {
                // The split-view app's bubble must read clearly even when the
                // user has the opacity slider down low, so pin it to full alpha.
                alpha = 1.0;
            } else {
                // The dimmed bubbles use a fixed fraction independent of the
                // opacity slider; otherwise a low slider would push them nearly
                // invisible.
                alpha = NFBFloatingDim;
            }
        }
        // A bubble mid-shake (fresh notification during split view) stays fully
        // opaque for the reminder's duration, whatever its normal state is.
        if ([self.shakingApps containsObject:appID]) alpha = 1.0;
        BOOL changed = fresh || !CGRectEqualToRect(button.bounds, targetBounds) ||
            !CGPointEqualToPoint(button.center, targetCenter) ||
            !CGAffineTransformEqualToTransform(button.transform, target) ||
            fabs(button.alpha - alpha) > 0.001;
        if (changed) {
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : NFBMotion
                delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                animations:^{
                    // Bounds/center remain valid even while the view is transformed.
                    button.bounds = targetBounds;
                    button.center = targetCenter;
                    button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
                    button.imageView.layer.cornerRadius = isStorage ? diameter * 0.32 : diameter / 2;
                    button.transform = target;
                    button.alpha = alpha;
                } completion:nil];
        }
    }];
}
// One action per gesture. Without this, a bounce in the finger or a leftover
// second tap of a retired double-tap would fire close/exit twice in a row.
- (BOOL)acceptGesture {
    NSTimeInterval now = CACurrentMediaTime();
    if (now - self.lastGestureAt < NFBGestureCooldown) return NO;
    self.lastGestureAt = now;
    // While the folded stack is spread open, any tap keeps it open for another
    // NFBStackHold seconds — only 20 seconds of no action folds it back.
    if (self.stackUntil > now) self.stackUntil = now + NFBStackHold;
    return YES;
}
// A bubble belongs to the app currently occupying the TrollOpen floating window.
// Resolved through one place so tap and long press can never disagree.
- (BOOL)isFloatingBubble:(NFBBubble *)button {
    if (!button || self.buttons[button.appID] != button) return NO;
    NSString *floating = NFBTrollVisibleApp();
    return floating.length > 0 && [floating isEqualToString:button.appID];
}
// Grow the floating window back to fullscreen (single tap). Refreshes slightly
// later, because TrollOpen re-parents the scene across a run loop turn.
- (void)fullscreenFloatingApp:(NSString *)app {
    NFBDebugLog(@"gesture: tap on floating app %@ -> fullscreen", app);
    // Retract first, then hand off: both animations now start on the same frame
    // instead of the bubble waiting for TrollOpen to finish the transition.
    [self beginRetracting:app];
    if (!NFBFullscreenCurrentFloatingWindow())
        [self showOpenNotice:@"TrollOpen 全屏接口不可用，请确认已安装适配的 1.5.2 隐根版并重启桌面"];
}
- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    if (self.buttons[button.appID] != button) return;
    // Long press on the bubble that owns the floating window shrinks that window
    // back to its mini size (TrollOpen's "缩小浮窗"), instead of terminating it.
    if ([self isFloatingBubble:button]) {
        if (![self acceptGesture]) return;
        NSString *app = button.appID;
        NFBDebugLog(@"gesture: long press on floating app %@ -> minimize", app);
        [self beginRetracting:app];
        if (!NFBMinimizeCurrentFloatingWindow())
            [self showOpenNotice:@"TrollOpen 缩小浮窗接口不可用，请确认已安装适配的 1.5.2 隐根版并重启桌面"];
        return;
    }
    if (![self acceptGesture]) return;
    NSString *app = button.appID;
    // Suppress touch-up activation while the queued burst removes this control.
    button.opening = YES;
    button.userInteractionEnabled = NO;
    [self.dismissedSwitcher addObject:app];
    [self closeAppsInOrder:@[app]];
    dispatch_async(dispatch_get_main_queue(), ^{
        // If a new notification cancelled dismissal, leave that surviving icon usable.
        if (self.buttons[app] == button) {
            button.opening = NO; button.userInteractionEnabled = YES;
        }
    });
    // Let the burst read first, then terminate the process behind it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NFBDebugLog(@"gesture: long press on non-floating app %@ -> terminate", app);
        NFBTerminateApp(app);
        [self refresh];
    });
}
- (void)burstBubble:(NFBBubble *)button {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.15 animations:^{ button.alpha = 0; }
            completion:^(__unused BOOL done) { [button removeFromSuperview]; }];
        return;
    }
    UIView *root = self.window.rootViewController.view;
    // Capture presentation geometry so a long press during sliding does not jump.
    CALayer *presentation = (CALayer *)button.layer.presentationLayer;
    CALayer *sourceLayer = presentation ?: button.layer;
    CGPoint origin = [sourceLayer convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toLayer:root.layer];
    CGFloat diameter = button.imageView.bounds.size.width;
    origin.x = MIN(origin.x, root.bounds.size.width - diameter * 0.15);
    UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(origin.x - diameter/2, origin.y - diameter/2, diameter, diameter)];
    ring.userInteractionEnabled = NO;
    ring.layer.cornerRadius = diameter/2;
    ring.layer.borderWidth = 2;
    ring.layer.borderColor = UIColor.systemTealColor.CGColor;
    ring.alpha = self.iconOpacity;
    [root addSubview:ring];
    [UIView animateWithDuration:0.55 animations:^{
        ring.transform = CGAffineTransformMakeScale(1.65, 1.65); ring.alpha = 0;
    } completion:^(__unused BOOL done) { [ring removeFromSuperview]; }];
    for (NSInteger i = 0; i < 12; i++) {
        CGFloat angle = (2 * M_PI * i) / 12;
        UIView *drop = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 4 + (i % 3), 4 + (i % 3))];
        drop.center = CGPointMake(origin.x + cos(angle)*diameter*0.32, origin.y + sin(angle)*diameter*0.32);
        drop.layer.cornerRadius = drop.bounds.size.width/2;
        drop.backgroundColor = i % 2 ? UIColor.systemTealColor : UIColor.whiteColor;
        drop.userInteractionEnabled = NO; drop.alpha = self.iconOpacity;
        [root addSubview:drop];
        [UIView animateWithDuration:0.55 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            drop.center = CGPointMake(origin.x + cos(angle)*diameter*0.95, origin.y + sin(angle)*diameter*0.95);
            drop.alpha = 0; drop.transform = CGAffineTransformMakeScale(0.15, 0.15);
        } completion:^(__unused BOOL done) { [drop removeFromSuperview]; }];
    }
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        button.transform = CGAffineTransformScale(button.transform, 1.16, 1.16); button.alpha = 0;
    } completion:^(__unused BOOL done) { [button removeFromSuperview]; }];
}
- (void)styleStorageButton:(NFBBubble *)button count:(NSUInteger)count {
    button.imageView.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill"];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.imageView.tintColor = UIColor.labelColor;
    button.imageView.backgroundColor = UIColor.clearColor;
    button.imageView.layer.borderWidth = 0.5;
    button.imageView.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
    UIVisualEffectView *material = (UIVisualEffectView *)[button.imageView viewWithTag:39001];
    if (!material) {
        material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        material.tag = 39001; material.userInteractionEnabled = NO;
        material.frame = button.imageView.bounds;
        material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [button.imageView insertSubview:material atIndex:0];
        // UIImageView draws its own image behind subviews; use a foreground glyph.
        UIImageView *glyph = [[UIImageView alloc] initWithImage:button.imageView.image];
        glyph.contentMode = UIViewContentModeCenter; glyph.tintColor = UIColor.labelColor;
        glyph.frame = material.bounds; glyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [material.contentView addSubview:glyph];
    }
    button.imageView.image = nil;
    button.badge.hidden = NO;
    button.badge.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)count];
    button.badge.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.badge.textColor = UIColor.secondaryLabelColor;
    CGFloat width = count > 99 ? 28 : 22;
    button.badge.frame = CGRectMake(self.iconSize + 14 - width, self.iconSize - 8, width, 18);
    button.badge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    button.badge.layer.cornerRadius = 9;
    button.accessibilityLabel = [NSString stringWithFormat:@"收纳了 %lu 个应用", (unsigned long)count];
    button.accessibilityHint = @"点击展开，20 秒无操作后自动收起";
}
- (void)storageTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || ![self acceptGesture]) return;
    self.stackUntil = CACurrentMediaTime() + NFBStackHold;
    [self refresh];
}
- (void)singleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    [self tapped:button];
}
- (void)tapped:(NFBBubble *)button {
    if (button.opening || self.buttons[button.appID] != button) return;
    if (self.pendingRecord && [self.pendingRecord.appID isEqual:button.appID]) return;
    if (![self acceptGesture]) return;
    button.opening = YES;
    [self extendApp:button.appID];
    [self refresh]; // Starts the same 0.6-second animation used for retraction.
    NFBRecord *record = [self.store latestForApp:button.appID];
    // Dispatch in this same event, never in the animation completion.
    if (record) {
        BOOL locked = [self isLocked];
        if ([self executeRecord:record]) {
            if (locked) { self.pendingRecord = record; self.pendingUntil = CACurrentMediaTime() + 20; }
            else [self.store consumeRecord:record];
        }
    } else [self openApp:button.appID];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ button.opening = NO; });
}
- (void)showOpenNotice:(NSString *)message {
    // A non-modal message keeps the overlay from taking keyboard or app focus.
    [self ensureWindow];
    UILabel *notice = [UILabel new];
    notice.text = message; notice.numberOfLines = 0;
    notice.textAlignment = NSTextAlignmentCenter;
    notice.font = [UIFont systemFontOfSize:14];
    notice.textColor = UIColor.whiteColor;
    notice.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.85];
    notice.layer.cornerRadius = 12; notice.clipsToBounds = YES;
    notice.userInteractionEnabled = NO;
    UIView *root = self.window.rootViewController.view;
    CGFloat width = MIN(320, root.bounds.size.width - 32);
    notice.frame = CGRectMake((root.bounds.size.width - width) / 2,
        MAX(root.safeAreaInsets.top, 44) + 12, width, 76);
    [root addSubview:notice];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    [UIView animateWithDuration:0.2 delay:2.8 options:0 animations:^{ notice.alpha = 0; }
        completion:^(__unused BOOL done) { [notice removeFromSuperview]; }];
}
- (void)openApp:(NSString *)app {
    if ([self isLocked]) {
        [self showOpenNotice:@"请先解锁，再点击图标通过 TrollOpen 分屏打开"];
        return;
    }
    CFStringRef domain = CFSTR("com.charlieleung.trollopenjbprefs");
    CFPreferencesAppSynchronize(domain);
    id enabled = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), domain));
    if (![enabled respondsToSelector:@selector(boolValue)] || ![enabled boolValue]) {
        [self showOpenNotice:@"请先安装并在设置中启用 TrollOpen"];
        return;
    }
    // Reached only with no unread notification left: on the app that currently
    // owns the floating window, a single tap grows that window to fullscreen.
    if ([NFBTrollVisibleApp() isEqualToString:app]) {
        [self fullscreenFloatingApp:app];
        return;
    }
    id springboard = UIApplication.sharedApplication;
    NSString *front = NFBString(NFBGet(NFBGet(springboard, @"_accessibilityFrontMostApplication"), @"bundleIdentifier"));
    BOOL home = [springboard respondsToSelector:@selector(isShowingHomescreen)] && [springboard isShowingHomescreen];
    BOOL submitted;
    if (!home && [front isEqualToString:app]) {
        // Do not fall back to the generic path: that path left a black backdrop
        // when the very same app was still occupying the fullscreen scene.
        submitted = NFBSplitTrollFrontmostApp();
    } else {
        submitted = NFBOpenTrollApp(app);
    }
    if (!submitted)
        [self showOpenNotice:@"TrollOpen 分屏接口不可用，请确认已安装适配的 1.5.2 隐根版并重启桌面"];
}
- (BOOL)executeRecord:(NFBRecord *)record {
    id action = NFBGet(record.request, @"defaultAction");
    id delegate = NFBGet(record.destination, @"delegate");
    SEL selector = @selector(destination:executeAction:forNotificationRequest:requestAuthentication:withParameters:completion:);
    NSMethodSignature *signature = [delegate methodSignatureForSelector:selector];
    BOOL compatible = signature && signature.numberOfArguments == 8 &&
        signature.methodReturnType[0] == 'v';
    if (compatible) {
        for (NSUInteger i = 2; i < 8; i++) {
            char type = [signature getArgumentTypeAtIndex:i][0];
            if (i == 5) compatible = compatible && (type == 'B' || type == 'c');
            else compatible = compatible && type == '@';
        }
    }
    if (!record || !action || ![delegate respondsToSelector:selector] || !compatible) {
        NSLog(@"[NotifyBubbles] Notification action adapter unavailable; bubbles retained.");
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"暂时无法打开，请使用原通知");
        return NO;
    }
    @try {
        [delegate destination:record.destination executeAction:action forNotificationRequest:record.request
            requestAuthentication:YES withParameters:@{} completion:^{}];
        return YES;
    } @catch (__unused NSException *error) {
        NSLog(@"[NotifyBubbles] Notification action failed; bubbles retained.");
        return NO;
    }
}
@end
