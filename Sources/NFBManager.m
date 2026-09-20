#import "NFBManager.h"
#import "NFBPrivate.h"
#import "NFBStore.h"
#import "NFBGeometry.h"
#import "NFBSwitcher.h"
#import "NFBTrollOpen.h"
#import "NFBNotificationPolicy.h"
#import "NFBAppExit.h"
#import "NFBDebugLog.h"

static const NSTimeInterval NFBMotion = 0.6;
// How long a bubble stays expanded after an unread arrives.
static const NSTimeInterval NFBHold = 1.0;
// Double-tap is intentionally inert, so a single tap no longer has to wait for a
// possible second tap: the recognizer fires on touch-up with no arbitration lag.
// This guard only swallows the accidental repeat that follows a real double tap.
static const NSTimeInterval NFBGestureCooldown = 0.25;
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
- (void)refresh;
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
        _dismissedSwitcher = [NSMutableSet set];
        _generations = [NSMutableDictionary dictionary];
        _needsReveal = [NSMutableSet set];
        _lastBadges = [NSMutableDictionary dictionary];
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
    return apps.array;
}
- (void)clear {
    [self.dismissedSwitcher addObjectsFromArray:self.lastSwitcher ?: @[]];
    [self closeAppsInOrder:[self orderedAppsForRemoval]];
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
    id badge = NFBGet(icon, @"badgeNumberOrString");
    NSString *text = nil;
    if ([badge isKindOfClass:NSNumber.class] && [badge longLongValue] > 0) text = [badge stringValue];
    if ([badge isKindOfClass:NSString.class] && [badge length] && ![badge isEqualToString:@"0"]) text = badge;
    button.badge.hidden = !text.length;
    button.badge.text = text;
    CGFloat width = MAX(20, [text sizeWithAttributes:@{NSFontAttributeName:button.badge.font}].width + 10);
    button.badge.frame = CGRectMake(0, 0, width, 20);
    NSString *name = NFBString(NFBGet(icon, @"displayName")) ?: button.appID;
    button.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", name, text ?: (record ? @"有通知" : @"暂无新通知")];
    button.accessibilityHint = @"点击打开通知，无通知时通过 TrollOpen 分屏打开，长按关闭图标";
    NSNumber *previous = self.lastBadges[button.appID];
    if (previous.doubleValue > 0 && (!text.length || [text isEqualToString:@"0"]))
        [self.store removeApp:button.appID];
    if ([badge isKindOfClass:NSNumber.class]) self.lastBadges[button.appID] = badge;
    else if (!text.length) self.lastBadges[button.appID] = @0;
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
    NSMutableArray<NSString *> *apps = [NSMutableArray array];
    for (NSString *app in self.store.appIDs) {
        BOOL fromSwitcher = [self.lastSwitcher containsObject:app];
        BOOL notificationsAllowed = NFBSystemNotificationsAllowed(app, ^{ [self refresh]; });
        if (fromSwitcher || notificationsAllowed) [apps addObject:app];
    }
    NSString *floatingApp = NFBTrollVisibleApp();
    id springboard = UIApplication.sharedApplication;
    BOOL home = [springboard respondsToSelector:@selector(isShowingHomescreen)] && [springboard isShowingHomescreen];
    NSString *active = floatingApp ?: (home ? nil : NFBString(NFBGet(NFBGet(springboard, @"_accessibilityFrontMostApplication"), @"bundleIdentifier")));
    if (active.length && [apps containsObject:active]) {
        [apps removeObject:active]; [apps insertObject:active atIndex:0];
        if (![self.lastActiveApp isEqual:active]) [self.store promoteApp:active];
    }
    self.lastActiveApp = active;
    BOOL orderChanged = ![self.lastLayoutApps isEqualToArray:apps];
    self.lastLayoutApps = [apps copy];
    for (NSString *appID in self.buttons.allKeys) {
        if ([apps containsObject:appID]) continue;
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
        if ([self.store.appIDs containsObject:app]) [self extendApp:app];
        [self.needsReveal removeObject:app];
    }
    UIView *root = self.window.rootViewController.view;
    CGRect bounds = root.bounds;
    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat top = MAX(safe.top, 48) + 30;
    CGFloat diameter = self.iconSize;
    CGFloat side = diameter + 14;
    CGFloat step = side + 4;
    CGFloat available = MAX(side, bounds.size.height - top - MAX(safe.bottom, 20) - 20);
    CGFloat height = MIN(available, apps.count * step);
    // Use the actual screen edge, not safeArea.right, for exactly half exposure.
    CGRect railFrame = CGRectMake(bounds.size.width - side, top + (available - height) * self.verticalPosition, side, height);
    if (!CGRectEqualToRect(self.rail.frame, railFrame)) {
        if (CGRectIsEmpty(self.rail.frame)) self.rail.frame = railFrame;
        else [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : NFBMotion delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
            animations:^{ self.rail.frame = railFrame; } completion:nil];
    }
    self.rail.contentSize = CGSizeMake(side, apps.count * step);
    CGFloat maxOffset = MAX(0, self.rail.contentSize.height - height);
    if (orderChanged || self.rail.contentOffset.y > maxOffset) self.rail.contentOffset = CGPointMake(0, maxOffset);
    [apps enumerateObjectsUsingBlock:^(NSString *appID, NSUInteger index, __unused BOOL *stop) {
        NFBBubble *button = self.buttons[appID];
        BOOL fresh = !button;
        if (fresh) {
            button = [[NFBBubble alloc] initWithFrame:CGRectZero];
            button.appID = appID;
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
            self.buttons[appID] = button;
            [self.rail addSubview:button];
        }
        [self updateBubble:button record:[self.store latestForApp:appID]];
        BOOL expanded = [floatingApp isEqualToString:appID] || [self.expandedUntil[appID] doubleValue] > CACurrentMediaTime();
        CGAffineTransform target = CGAffineTransformMakeTranslation(expanded ? 0 : NFBRetraction(diameter), 0);
        CGRect targetBounds = CGRectMake(0, 0, side, side);
        CGPoint targetCenter = CGPointMake(side / 2, NFBRowCenter(apps.count, index, step, side));
        if (fresh) {
            button.bounds = targetBounds;
            button.center = targetCenter;
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = diameter / 2;
            button.transform = CGAffineTransformMakeTranslation(side + 10, 0);
            button.alpha = 0;
        }
        BOOL changed = fresh || !CGRectEqualToRect(button.bounds, targetBounds) ||
            !CGPointEqualToPoint(button.center, targetCenter) ||
            !CGAffineTransformEqualToTransform(button.transform, target) ||
            fabs(button.alpha - self.iconOpacity) > 0.001;
        if (changed) {
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : NFBMotion
                delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                animations:^{
                    // Bounds/center remain valid even while the view is transformed.
                    button.bounds = targetBounds;
                    button.center = targetCenter;
                    button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
                    button.imageView.layer.cornerRadius = diameter / 2;
                    button.transform = target;
                    button.alpha = self.iconOpacity;
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
    return YES;
}
// A bubble belongs to the app currently occupying the TrollOpen floating window.
// Resolved through one place so tap and long press can never disagree.
- (BOOL)isFloatingBubble:(NFBBubble *)button {
    if (!button || self.buttons[button.appID] != button) return NO;
    NSString *floating = NFBTrollVisibleApp();
    return floating.length > 0 && [floating isEqualToString:button.appID];
}
// Close the floating window (single tap). Refreshes slightly later, because
// TrollOpen tears the window down across a run loop turn.
- (void)closeFloatingWindowForApp:(NSString *)app {
    NFBDebugLog(@"gesture: tap on floating app %@ -> close", app);
    if (!NFBCloseCurrentFloatingWindow()) {
        [self showOpenNotice:@"TrollOpen 关闭分屏接口不可用，请确认已安装适配的 1.5.2 隐根版并重启桌面"];
        return;
    }
    [self.expandedUntil removeObjectForKey:app];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refresh]; });
}
// Quit the app the way the App Switcher's swipe-up does (long press).
- (void)exitApp:(NSString *)app {
    NFBDebugLog(@"gesture: long press on floating app %@ -> exit", app);
    if (!NFBTerminateApp(app)) {
        [self showOpenNotice:@"未能退出该 App，请确认插件已注入桌面并重启桌面"];
        return;
    }
    [self.expandedUntil removeObjectForKey:app];
    // Termination normally takes the floating window with it. If TrollOpen still
    // reports this app as visible afterwards, its window survived the process
    // death and is now empty — close exactly that window, never another one.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([NFBTrollVisibleApp() isEqualToString:app]) NFBCloseCurrentFloatingWindow();
        [self refresh];
    });
}
- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    if (self.buttons[button.appID] != button) return;
    // Long press on the floating app's bubble quits the app; everything else
    // keeps the original burst that clears that app's notifications.
    if ([self isFloatingBubble:button]) {
        if (![self acceptGesture]) return;
        [self exitApp:button.appID];
        return;
    }
    if (![self acceptGesture]) return;
    // Suppress touch-up activation while the queued burst removes this control.
    button.opening = YES;
    button.userInteractionEnabled = NO;
    [self.dismissedSwitcher addObject:button.appID];
    [self closeAppsInOrder:@[button.appID]];
    dispatch_async(dispatch_get_main_queue(), ^{
        // If a new notification cancelled dismissal, leave that surviving icon usable.
        if (self.buttons[button.appID] == button) {
            button.opening = NO; button.userInteractionEnabled = YES;
        }
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
    // owns the floating window, a single tap closes that window.
    if ([NFBTrollVisibleApp() isEqualToString:app]) {
        [self closeFloatingWindowForApp:app];
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
