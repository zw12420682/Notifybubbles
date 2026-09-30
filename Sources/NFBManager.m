#import "NFBManager.h"
#import "NFBPrivate.h"
#import "NFBStore.h"
#import "NFBGeometry.h"
#import "NFBStorageLayout.h"
#import "NFBSwitcher.h"
#import "NFBTrollOpen.h"
#import "NFBWindowControls.h"
#import "NFBNotificationPolicy.h"
#import "NFBAppExit.h"
#import "NFBKeyboard.h"
#import "NFBDebugLog.h"
#import "NFBEdgeInspection.h"
#import "NFBEdgeLayout.h"
#import "NFBPrivacy.h"
#import "NFBContainerLayout.h"

static const NSTimeInterval NFBMotion = 0.35;
// How long a bubble stays expanded after an unread arrives.
static const NSTimeInterval NFBHold = 1.0;
// No double-tap recognizer: a short tap resolves on release.
// Guard against repeated callbacks from the same completed gesture.
static const NSTimeInterval NFBGestureCooldown = 0.25;
// While an app sits in the split view its bubble stays fully opaque (alpha 1.0,
// independent of the user's opacity slider) and every other bubble drops to this
// fraction, so the split-view app reads as the active one without being pulled
// to the top of the row.

// Vertical position (0 = top, 1 = bottom) the whole row shifts to while an app
// is in the split view, so it clears the floating window. Restores on exit.
static const CGFloat NFBFloatingPosition = 0.80;
// Vertical position the row shifts to while the keyboard is up, so the bubbles
// clear the keyboard. Applies in BOTH split view and fullscreen, and outranks
// every other position rule.
static const CGFloat NFBKeyboardPosition = 0.49;
// How long the folded (no-unread) bubbles stay spread out after a tap on the
// stack edge, before folding back into a thin stack.
static const NSTimeInterval NFBStackHold = 4.0;
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
@property(nonatomic) BOOL containerMode;
@end
@implementation NFBRail
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.containerMode) return [super pointInside:point withEvent:event];
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
@property(nonatomic, strong) UIView *activeMark;
- (void)updateActiveMark:(BOOL)active diameter:(CGFloat)diameter duration:(NSTimeInterval)duration;
@property(nonatomic) BOOL opening;
@property(nonatomic) BOOL holdStartedRetracted;
@end
@implementation NFBBubble
- (void)updateActiveMark:(BOOL)active diameter:(CGFloat)diameter duration:(NSTimeInterval)duration {
    // The bottom seven-point inset contains the whole mark: never extend past the row.
    CGRect frame = CGRectMake(7 + diameter * 0.30, 7 + diameter + 2, diameter * 0.40, 3);
    CGFloat alpha = active ? 1 : 0;
    if (CGRectEqualToRect(self.activeMark.frame, frame) && self.activeMark.alpha == alpha) return;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : duration
        delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.activeMark.frame = frame;
        self.activeMark.alpha = alpha;
    } completion:nil];
}
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
        _activeMark = [UIView new];
        _activeMark.backgroundColor = UIColor.systemRedColor;
        _activeMark.userInteractionEnabled = NO;
        _activeMark.layer.cornerRadius = 1.5;
        _activeMark.alpha = 0;
        [self addSubview:_activeMark];
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.22;
        self.layer.shadowRadius = 5;
        self.layer.shadowOffset = CGSizeMake(0, 2);
    }
    return self;
}
@end

@interface NFBManager () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) NFBStore *store;
@property(nonatomic, strong) NFBWindow *window;
@property(nonatomic, strong) NFBRail *rail;
@property(nonatomic) BOOL backgroundCollapsed;
@property(nonatomic, strong) NFBBubble *topActionButton;
@property(nonatomic, strong) UITapGestureRecognizer *topActionTap;
@property(nonatomic, weak) UIView *topActionTarget;
@property(nonatomic, weak) UIView *topActionTouchTarget;
@property(nonatomic, weak) UIView *observedActionTarget;
@property(nonatomic) CGRect observedActionFrame;
@property(nonatomic) BOOL observedActionLandscape;
- (void)topActionTapped:(UITapGestureRecognizer *)gesture;
- (void)layoutTopAction:(CGRect)frame target:(UIView *)target duration:(NSTimeInterval)duration;

@property(nonatomic, strong) NFBRail *unreadRail;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *edgeCopies;
- (void)layoutEdgeCopies:(NSArray<NSString *> *)apps unread:(NSArray<NSString *> *)unread diameter:(CGFloat)diameter active:(NSString *)active duration:(NSTimeInterval)duration;
@property(nonatomic, strong) NFBRail *favoritesRail;
@property(nonatomic, strong) UIVisualEffectView *favoritesMaterial;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *favoriteButtons;
@property(nonatomic, copy) NSArray<NSString *> *favoriteApps;
@property(nonatomic, strong) UILongPressGestureRecognizer *favoriteHold;
@property(nonatomic, strong) NFBBubble *favoriteDrag;
@property(nonatomic, strong) NSTimer *favoriteDragTimer;
@property(nonatomic) CGFloat favoriteGrabOffset;
- (void)favoriteHeld:(UILongPressGestureRecognizer *)gesture;
- (void)moveFavorite;
- (void)finishFavoriteDrag;
- (void)saveFavoritePosition;
@property(nonatomic, copy) NSArray<NSString *> *backgroundOrder;
@property(nonatomic, copy) NSString *lastRailActive;
@property(nonatomic, copy) NSString *lastFavoritesActive;
- (void)clearAllHeld:(UILongPressGestureRecognizer *)gesture;
- (void)layoutFavorites:(CGRect)frame diameter:(CGFloat)diameter active:(NSString *)active duration:(NSTimeInterval)duration;

@property(nonatomic) NSTimeInterval edgeUntil;
@property(nonatomic) BOOL edgeMode;
@property(nonatomic, strong) UITapGestureRecognizer *edgeTap;
@property(nonatomic) BOOL draggingEdge;
@property(nonatomic) CGFloat dragStartY;
@property(nonatomic) CGFloat dragStartPosition;
@property(nonatomic) CGFloat dragSavedPosition;
@property(nonatomic) CGFloat edgeAvailable;
@property(nonatomic) CGFloat resolvedEdgePosition;
- (void)edgeLongPressed:(UILongPressGestureRecognizer *)gesture;
- (void)closeBubble:(NFBBubble *)button;
- (BOOL)edgeBubbleIsRetracted:(NFBBubble *)button;
- (void)extendEdgeContainer;
- (void)restartStorageIdleTimer;
- (void)edgeContainerTapped:(UITapGestureRecognizer *)gesture;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *buttons;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *expandedUntil;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *icons;
@property(nonatomic, strong) NSMutableSet<NSString *> *burstApps;
@property(nonatomic, strong) NSArray<NSString *> *lastSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *dismissedSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *closingApps;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *generations;
@property(nonatomic, strong) NSMutableSet<NSString *> *needsReveal;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastBadges;
@property(nonatomic, strong) NFBRecord *pendingRecord;
@property(nonatomic) NSTimeInterval pendingUntil;
@property(nonatomic) NSUInteger emptyReads;
@property(nonatomic) CGFloat verticalPosition;
@property(nonatomic, copy) NSString *lastActiveApp;
@property(nonatomic, strong) NSMutableArray<NSString *> *recentUsedApps;
@property(nonatomic, copy) NSArray *lastLayoutApps;
@property(nonatomic, copy) NSArray<NSString *> *storedApps;
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
@property(nonatomic) CGRect observedSplitFrame;
@property(nonatomic) BOOL splitRailActive;
@property(nonatomic) CGFloat splitRailDiameter;
@property(nonatomic, strong) UIVisualEffectView *railMaterial;
@property(nonatomic, copy) NSString *watchedFloating;
// Previous keyboard state, so refresh can spot the up/down edges.
@property(nonatomic) BOOL keyboardUp;
// Bubbles that were out when the keyboard rose; restored when it falls.
@property(nonatomic, strong) NSMutableSet<NSString *> *keyboardSuspended;
// Apps whose bubble is mid-shake (a new message arrived while an app sits in
// the split view). Kept full opacity for the shake's duration.
@property(nonatomic, strong) NSMutableSet<NSString *> *shakingApps;
- (void)refresh;
- (void)updatePrivacy;
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
        _closingApps = [NSMutableSet set];
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
    self.verticalPosition = NFBPosition(NFBNumber(@"EdgeVerticalPosition", NFBNumber(@"VerticalPosition", 0.7)));
    self.iconSize = NFBSize(NFBNumber(@"IconSize", 48));
    self.iconOpacity = NFBOpacity(NFBNumber(@"IconOpacity", 1));
    self.enabled = NFBPreference(@"Enabled", YES);
    self.showLock = NFBPreference(@"ShowOnLock", YES);
    self.showHome = NFBPreference(@"ShowOnHome", YES);
    self.showApps = NFBPreference(@"ShowInApps", YES);
    id favorites = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("FavoriteApps"), NFBDomain));
    NSMutableOrderedSet *selected = [NSMutableOrderedSet orderedSet];
    if ([favorites isKindOfClass:NSArray.class]) for (id app in favorites)
        if ([app isKindOfClass:NSString.class] && [app length]) [selected addObject:app];
    NSMutableOrderedSet *favoriteOrder = [NSMutableOrderedSet orderedSet];
    id savedOrder = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("FavoriteOrder"), NFBDomain));
    NSArray *order = self.favoriteApps ?: ([savedOrder isKindOfClass:NSArray.class] ? savedOrder : @[]);
    for (NSString *app in order) if ([selected containsObject:app]) [favoriteOrder addObject:app];
    [favoriteOrder addObjectsFromArray:selected.array];
    self.favoriteApps = favoriteOrder.array;
    if (!self.enabled) {
        NFBUpdateDesktopFreeze(NO, 0);
        NFBSetCaptureHidden(self.window.rootViewController.view, NO);
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
        UIScrollView *owner = [updated.superview isKindOfClass:UIScrollView.class] ? (UIScrollView *)updated.superview : nil;
        CGRect row = CGRectMake(0, updated.center.y - updated.bounds.size.height / 2, owner.bounds.size.width, updated.bounds.size.height);
        [owner scrollRectToVisible:row animated:!UIAccessibilityIsReduceMotionEnabled()];
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
    id sb = UIApplication.sharedApplication;
    NSString *front = nil;
    if ([sb respondsToSelector:@selector(isShowingHomescreen)] && ![sb isShowingHomescreen])
        front = NFBString(NFBGet(NFBGet(sb, @"_accessibilityFrontMostApplication"), @"bundleIdentifier"));
    NSMutableArray<NSString *> *targets = [NSMutableArray array];
    for (NSString *app in [self orderedAppsForRemoval]) {
        if ([app isEqualToString:floating] || [app isEqualToString:front]) continue;
        [targets addObject:app];
    }
    if (!targets.count) return;
    NFBDebugLog(@"gesture: clear-background -> %lu apps", (unsigned long)targets.count);
    [self.dismissedSwitcher addObjectsFromArray:targets];
    [self closeAppsInOrder:targets];
    [targets enumerateObjectsUsingBlock:^(NSString *app, __unused NSUInteger index, __unused BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.35 + index * 0.16) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NFBTerminateApp(app);
            [self refresh];
        });
    }];
}
- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.edgeMode || [self isLocked] || ![self acceptGesture]) return;
    if (!NFBCloseCurrentSplit()) [self showOpenNotice:@"未能读取 TrollOpen 右侧区域的单击接口"];
    [self refresh];
}
- (void)topActionTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !self.enabled || [self isLocked]) return;
    UIView *target = self.topActionTouchTarget;
    self.topActionTouchTarget = nil;
    if (!target || target != self.topActionTarget || target != NFBTopActionWindow()) { [self refresh]; return; }
    if (![self acceptGesture]) return;
    if (!NFBPerformTopLongPress(target)) [self showOpenNotice:@"TrollOpen 顶部长按接口不可用"];
    [self refresh];
}
- (void)layoutTopAction:(CGRect)frame target:(UIView *)target duration:(NSTimeInterval)duration {
    BOOL visible = target && !CGRectIsNull(frame) && !CGRectIsEmpty(frame) && self.enabled;
    self.topActionTarget = visible ? target : nil;
    if (!self.topActionButton && !visible) return;
    if (!self.topActionButton) {
        NFBBubble *button = [[NFBBubble alloc] initWithFrame:frame];
        button.badge.hidden = YES;
        button.imageView.contentMode = UIViewContentModeCenter;
        button.imageView.image = [UIImage systemImageNamed:@"rectangle.2.swap"] ?: [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"];
        button.imageView.tintColor = UIColor.systemGreenColor;
        button.imageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        button.accessibilityLabel = @"TrollOpen 顶部长按功能";
        button.accessibilityHint = @"点击执行此窗口顶部绿色区域的长按动作";
        self.topActionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(topActionTapped:)];
        self.topActionTap.delegate = self;
        [button addGestureRecognizer:self.topActionTap];
        button.alpha = 0;
        self.topActionButton = button;
        [self.window.rootViewController.view addSubview:button];
    }
    NFBBubble *button = self.topActionButton;
    CGFloat targetAlpha = visible ? (NFBWindowIsLandscape(target) ? 0.5 : 1.0) : 0;
    button.userInteractionEnabled = visible;
    if (visible && button.alpha < 0.01) button.frame = frame;
    [self.window.rootViewController.view bringSubviewToFront:button];
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : MAX(0.16, duration)
        delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:^{
        button.alpha = targetAlpha;
        if (visible) {
            button.frame = frame;
            CGFloat imageSide = MAX(1, frame.size.width - 14);
            button.imageView.frame = CGRectMake(7, 7, imageSide, imageSide);
            button.imageView.layer.cornerRadius = imageSide * 0.23;
        }
    } completion:nil];
}
- (void)clearAllHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || [self isLocked] || ![self acceptGesture]) return;
    [self clearBackground];
}
// Combined close/clear action: a blue close glyph, no badge,
// and an accessibility label so VoiceOver reads it as an action, not an app.
- (void)styleClearAllButton:(NFBBubble *)button {
    button.badge.hidden = YES;
    button.imageView.contentMode = UIViewContentModeCenter;
    button.imageView.image = [UIImage systemImageNamed:@"xmark"];
    button.imageView.tintColor = UIColor.systemBlueColor;
    button.imageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.accessibilityLabel = @"关闭分屏 / 清理后台";
    button.accessibilityHint = @"单击执行 TrollOpen 右侧区域关闭，长按清理后台";
}
// Reminder for a fresh notification while an app sits in the split view: a
// 2-second decaying horizontal shake plus a temporary full-opacity highlight,
// then the bubble settles back to whatever opacity the split-view layout assigns
// it. The button's transform is identity here (split view keeps every bubble
// expanded), so a layer translation never fights the retraction offset.
- (void)shakeBubble:(NFBBubble *)button {
    if (!button || !button.superview) return;
    NSString *appID = button.appID;
    if (self.rail.containerMode) {
        [button.layer removeAnimationForKey:@"NFBShake"];
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            pulse.values = @[@1, @0.94, @1, @0.97, @1];
            pulse.duration = 0.65;
            [button.imageView.layer addAnimation:pulse forKey:@"NFBContainerPulse"];
        }
        return;
    }
    [self.shakingApps addObject:appID];
    [button.layer removeAnimationForKey:@"NFBShake"];
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.duration = 2.0;
        shake.values = @[@0, @(-6), @6, @(-5.25), @5.25, @(-4.5), @4.5, @(-3.75), @3.75, @(-3), @3, @(-2.25), @2.25, @(-1.5), @1.5, @0];
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
    NFBObserveRotationLayout();
    [self updatePrivacy];
    NSString *now = NFBSplitAttachmentApp();
    NSString *currentApp = NFBTrollVisibleApp();
    // Orientation can change while app identity and window frame stay the same.
    NSString *switchApp = [self.retracting containsObject:currentApp ?: @""] ? nil : currentApp;
    NFBObserveSplitSwitch(switchApp, self.enabled && NFBPreference(@"ClosePreviousSplit", YES));
    CGRect frame = NFBSplitFrameInView(self.window.rootViewController.view);
    BOOL sameFrame = CGRectEqualToRect(frame, self.observedSplitFrame) ||
        (CGRectIsNull(frame) && CGRectIsNull(self.observedSplitFrame));
    UIView *actionTarget = NFBTopActionWindow();
    CGRect actionFrame = NFBWindowFrameInView(actionTarget, self.window.rootViewController.view);
    BOOL landscape = NFBWindowIsLandscape(actionTarget);
    BOOL sameActionFrame = CGRectEqualToRect(actionFrame, self.observedActionFrame) ||
        (CGRectIsNull(actionFrame) && CGRectIsNull(self.observedActionFrame));
    if ((now == self.watchedFloating || [now isEqualToString:self.watchedFloating]) && sameFrame &&
        actionTarget == self.observedActionTarget && sameActionFrame && landscape == self.observedActionLandscape) return;
    self.observedActionTarget = actionTarget; self.observedActionFrame = actionFrame;
    self.observedActionLandscape = landscape;
    self.observedSplitFrame = frame;
    self.watchedFloating = now;
    [self refresh];
}
- (void)extendApp:(NSString *)app {
    if (self.edgeMode) [self extendEdgeContainer];
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
            if (self.generations[app] != versions[app] && ![self.generations[app] isEqual:versions[app]]) return;
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
    self.rail.delegate = self;
    UITapGestureRecognizer *edgeTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(edgeContainerTapped:)];
    self.edgeTap = edgeTap;
    edgeTap.cancelsTouchesInView = NO;
    edgeTap.delegate = self;
    [self.rail addGestureRecognizer:edgeTap];
    self.rail.showsVerticalScrollIndicator = NO;
    self.rail.alwaysBounceVertical = NO;
    self.railMaterial = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    self.railMaterial.userInteractionEnabled = NO;
    self.railMaterial.layer.cornerRadius = 20;
    self.railMaterial.clipsToBounds = YES;
    self.railMaterial.alpha = 0;
    [self.window.rootViewController.view addSubview:self.railMaterial];
    [self.window.rootViewController.view addSubview:self.rail];
    self.unreadRail = [NFBRail new];
    self.unreadRail.clipsToBounds = YES;
    self.unreadRail.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.unreadRail.showsVerticalScrollIndicator = NO;
    self.unreadRail.backgroundColor = UIColor.clearColor;
    [self.window.rootViewController.view addSubview:self.unreadRail];
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
    button.badge.font = [UIFont boldSystemFontOfSize:12];
    button.badge.layer.cornerRadius = 10;
    NSUInteger unread = [self.store countForApp:button.appID];
    NSString *text = unread > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)unread] : nil;
    button.badge.hidden = !text.length;
    button.badge.text = text;
    CGFloat width = MAX(20, [text sizeWithAttributes:@{NSFontAttributeName:button.badge.font}].width + 10);
    button.badge.frame = CGRectMake(0, 0, width, 20);
    NSString *name = NFBString(NFBGet(icon, @"displayName")) ?: button.appID;
    button.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", name, text ?: (record ? @"有通知" : @"暂无新通知")];
    button.accessibilityHint = @"点击伸出并打开；缩回时长按拖动，伸出后长按清除图标及 App";
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
- (void)updatePrivacy {
    id desktopSB = UIApplication.sharedApplication;
    BOOL desktopVisible = [desktopSB respondsToSelector:@selector(isShowingHomescreen)] && [desktopSB isShowingHomescreen];
    // Attachment lookup includes all expanded portrait windows, even behind a landscape window.
    BOOL splitVisible = NFBSplitAttachmentApp().length > 0;
    NFBUpdateDesktopFreeze(self.enabled && NFBPreference(@"FreezeDesktop", NO) &&
        desktopVisible && ![self isLocked] && splitVisible,
        1.0 - NFBNumber(@"DesktopBlurTransparency", 35) / 100.0);
    NFBSetCaptureHidden(self.window.rootViewController.view, self.enabled && NFBPreference(@"HideInScreenshots", NO));
}
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    [self updatePrivacy];
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
    if (reopened.length && ![self.closingApps containsObject:reopened] && [self.dismissedSwitcher containsObject:reopened]) {
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
    if ([self.retracting containsObject:floatingApp ?: @""]) floatingApp = nil;
    NFBObserveSplitSwitch(floatingApp, NFBPreference(@"ClosePreviousSplit", YES));
    NFBObserveRotationLayout();
    NFBObserveSplitPlacement(floatingApp);
    // An attachment fallback is layout-only: do not treat it as an app switch.
    floatingApp = NFBSplitAttachmentApp();
    if ([self.retracting containsObject:floatingApp ?: @""]) floatingApp = nil;
    // Keep the fast watcher in step with reality every time we recompute layout.
    // Continue observing orientation even when a lone landscape window has no
    // portrait attachment target and its rail has returned to the screen edge.
    [self syncFloatingWatch:floatingApp ?: NFBTrollVisibleApp() ?: (NFBTopActionWindow() ? @"__top_action__" : nil)];
    // A keyboard outranks everything else: typing is the one moment the bubbles
    // must be out of the way, so it pulls them all back in no matter what. The
    // ones it pulled in are remembered and popped back out the moment typing
    // ends (split-view bubbles come back on their own via floatingApp below).
    BOOL previousKeyboardUp = self.keyboardUp;
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
    BOOL edgeMode = !floatingApp.length;
    NSString *active = NFBTrollVisibleApp() ?: floatingApp ?: (home ? nil : NFBString(NFBGet(NFBGet(springboard, @"_accessibilityFrontMostApplication"), @"bundleIdentifier")));
    NSString *frontApp = home ? nil : NFBString(NFBGet(NFBGet(springboard, @"_accessibilityFrontMostApplication"), @"bundleIdentifier"));
    NSString *fullscreenApp = edgeMode && ![self isLocked] && frontApp.length &&
        ![frontApp isEqual:@"com.apple.springboard"] && ![frontApp isEqual:NFBTrollVisibleApp()] &&
        ![self.closingApps containsObject:frontApp] ? frontApp : nil;
    if (fullscreenApp.length && ![apps containsObject:fullscreenApp]) [apps addObject:fullscreenApp];
    // Recency decides membership, never a forced jump of an existing icon.
    if (active.length && ![self.closingApps containsObject:active] && ![self.dismissedSwitcher containsObject:active] && ![apps containsObject:active])
        [apps addObject:active];
    if (!self.recentUsedApps) self.recentUsedApps = [NSMutableArray array];
    if (active.length && ![self.lastActiveApp isEqual:active]) {
        [self.recentUsedApps removeObject:active];
        [self.recentUsedApps insertObject:active atIndex:0];
    }
    self.lastActiveApp = active;
    if (floatingApp.length) NFBInspectTrollEdges();
    self.edgeMode = edgeMode;
    NSMutableOrderedSet *history = [NSMutableOrderedSet orderedSetWithArray:self.recentUsedApps];
    [history addObjectsFromArray:self.lastSwitcher ?: @[]];
    // No external unread strip: the edge container owns every visible app.
    NSArray<NSString *> *unreadApps = @[];
    NSArray<NSString *> *allEdgeApps = NFBStableApps(apps, history.array, self.backgroundOrder ?: @[]);
    self.backgroundOrder = allEdgeApps;
    NSArray<NSString *> *railApps;
    NSUInteger storedCount = 0;
    if (edgeMode) {
        railApps = NFBVisibleEdgeAppsExcludingFullscreen(allEdgeApps, fullscreenApp, self.backgroundCollapsed, ^NSUInteger(NSString *app) {
            return [self.store countForApp:app];
        });
        for (NSString *app in allEdgeApps) if (![app isEqual:fullscreenApp] && ![self.store countForApp:app]) storedCount++;
    } else {
        // Membership, not merely viewport height, is limited to two recent apps.
        NSMutableArray<NSString *> *background = [NSMutableArray array];
        for (NSString *app in apps)
            if ([self.lastSwitcher containsObject:app] || [app isEqual:active]) [background addObject:app];
        railApps = NFBRecentBackgroundThree(background, history.array, self.favoriteApps);
    }
    NSMutableArray<NSString *> *displayApps = [railApps mutableCopy];
    if (fullscreenApp.length) [displayApps addObject:fullscreenApp];
    [displayApps addObject:edgeMode ? NFBStorageID : NFBClearAllID];
    self.storedApps = @[];
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
    if (!self.enabled) {
        // Delay hiding until the removal animation completes; recheck new arrivals.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.enabled || !self.buttons.count) self.window.hidden = YES;
        });
        return;
    }
    if (![self shouldShow]) { self.window.hidden = YES; return; }
    [self ensureWindow];
    NFBSetCaptureHidden(self.window.rootViewController.view, NFBPreference(@"HideInScreenshots", NO));
    self.window.hidden = NO;
    for (NSString *app in [self.needsReveal copy]) {
        // An open keyboard outranks even a fresh notification: leave the reveal
        // pending instead of burning it, so it shows the moment typing ends.
        if (keyboardUp) break;
        if ([self.store.appIDs containsObject:app]) [self extendApp:app];
        [self.needsReveal removeObject:app];
    }
    UIView *root = self.window.rootViewController.view;
    CGFloat oldBottomOffset = MAX(0, self.rail.contentSize.height - self.rail.bounds.size.height) - self.rail.contentOffset.y;
    CGRect bounds = root.bounds;
    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat top = MAX(safe.top, 48) + 30;
    CGRect splitFrame = floatingApp.length ? NFBSplitFrameInView(root) : CGRectNull;
    BOOL attached = !NFBCurrentSplitLandscape() && floatingApp.length && !CGRectIsNull(splitFrame) && !CGRectIsEmpty(splitFrame);
    BOOL containerMode = !edgeMode;
    BOOL attachmentChanged = attached != self.splitRailActive;
    self.splitRailActive = attached;
    CGFloat diameter = self.iconSize;
    // Reserve a real gap outside the split window; never change its scale.
    // Only horizontal space constrains icon size, not app count or keyboard height.
    const CGFloat splitGap = 4;
    const CGFloat screenMargin = 4;
    if (attached) {
        CGFloat room = CGRectGetWidth(bounds) - CGRectGetMaxX(splitFrame) - splitGap - screenMargin;
        diameter = MIN(diameter, MAX(1, room - 14));
    }
    NSTimeInterval layoutDuration = (UIAccessibilityIsReduceMotionEnabled() || self.draggingEdge) ? 0 : (attachmentChanged ? 0.35 : (attached ? 0.16 : NFBMotion));
    CGFloat side = diameter + 14;
    CGFloat step = diameter + 9;
    CGFloat available = MAX(side, bounds.size.height - top - MAX(safe.bottom, 20) - 20);
    // Reserve space for badge/shadow and the shake's negative excursion.
    // Compact rows have step < side, so their bottom otherwise clips by 6pt.
    CGFloat padding = 12;
    CGFloat railWidth = side;
    NSUInteger rowCount = railApps.count;
    CGFloat contentHeight = rowCount ? (rowCount - 1) * step + side : 0;
    CGFloat height = MIN(available, contentHeight);
    // Keyboard outranks every other rule (typing must never be covered): the row
    // shifts to NFBKeyboardPosition in both split view and fullscreen. Otherwise,
    // while an app is in the split view the row shifts down to clear the floating
    // window (NFBFloatingPosition), then returns to the user's slider setting.
    CGFloat position = keyboardUp && !self.draggingEdge ? NFBKeyboardPosition : (floatingApp.length > 0 ? NFBFloatingPosition : self.verticalPosition);
    // Anchor the FIRST bubble (index 0, the lowest one) to a fixed screen Y so it
    // never moves: each new bubble stacks upward on top of it. The first bubble's
    // center sits (step - side/2) above the rail's bottom edge, so fixing the
    // rail's bottom edge fixes the first bubble. Anchoring the top edge instead
    // would make the row grow both up and down as bubbles arrive (spreading from
    // the middle), which is not what we want.
    CGFloat anchor = top + available * position;
    // Use the actual screen edge, not safeArea.right, for exactly half exposure.
    CGFloat railY = anchor + (step - side/2) + padding - height;
    railY = MAX(top, MIN(bounds.size.height - MAX(safe.bottom, 20) - 20 - height, railY));
    CGRect railFrame = CGRectMake(bounds.size.width - railWidth, railY, railWidth, height);
    if (attached) {
        CGFloat y = MAX(safe.top, CGRectGetMinY(splitFrame));
        CGFloat bottom = MIN(CGRectGetHeight(bounds) - safe.bottom, CGRectGetMaxY(splitFrame));
        height = MAX(1, bottom - y);
        CGFloat x = CGRectGetMaxX(splitFrame) + splitGap;
        railFrame = CGRectMake(x, y, railWidth, height);
    }
    CGFloat clearCenterY = railFrame.origin.y - 8 - side / 2;
    CGRect favoritesFrame = CGRectZero;
    UIView *actionTarget = NFBTopActionWindow();
    BOOL actionLandscape = NFBWindowIsLandscape(actionTarget);
    CGRect actionWindowFrame = NFBWindowFrameInView(actionTarget, root);
    CGRect topActionFrame = CGRectNull;
    if (containerMode) {
        CGFloat ceiling = MAX(safe.top, 12);
        CGFloat floor = CGRectGetHeight(bounds) - MAX(safe.bottom, 12);
        if (attached) floor = MIN(floor, CGRectGetMaxY(splitFrame) - CGRectGetHeight(splitFrame) * 0.05);
        if (keyboardUp) floor = MIN(floor, NFBKeyboardTopInView(root) - 12 - step);
        CGFloat desiredTop = attached ? NFBSplitRailTop(CGRectGetMinY(splitFrame), CGRectGetHeight(splitFrame)) : railFrame.origin.y;
        CGFloat y = MAX(ceiling, MIN(desiredTop, floor - side - 9));
        // The action occupies its own row above both rails, never inside scrolling content.
        if (actionTarget && !actionLandscape && !CGRectIsNull(actionWindowFrame) && floor - y >= 2 * side + 18) {
            topActionFrame = CGRectMake(railFrame.origin.x, y, side, side);
            y += side + 9;
        }
        CGFloat room = MAX(0, floor - y - side - 9);
        NFBContainerHeights fit = NFBFitContainers(room, side, step, self.favoriteApps.count, rowCount);
        CGFloat favoriteHeight = fit.favorites, gap = fit.gap;
        height = fit.regular;
        favoritesFrame = CGRectMake(railFrame.origin.x, y, railWidth, favoriteHeight);
        railFrame = CGRectMake(railFrame.origin.x, y + favoriteHeight + gap, railWidth, height);
        clearCenterY = CGRectGetMaxY(railFrame) + 9 + side / 2;
    }
    CGRect unreadFrame = CGRectZero;
    CGFloat unreadContentHeight = unreadApps.count ? (unreadApps.count - 1) * step + side : 0;
    if (edgeMode) {
        CGFloat edgeFloor = keyboardUp ? NFBKeyboardTopInView(root) - 12 - step
            : CGRectGetHeight(bounds) - MAX(safe.bottom, 12);
        CGFloat outsideHeight = fullscreenApp.length ? side + 9 : 0;
        CGFloat room = MAX(0, edgeFloor - top - side - 9 - outsideHeight);
        height = MIN(MIN(6 * step + side, contentHeight), room);
        // Reserve a separate transparent strip for unread apps above the container.
        CGFloat gap = height > 0 && unreadApps.count ? 9 : 0;
        CGFloat unreadHeight = MIN(unreadContentHeight, MAX(0, room - height - gap));
        // On short keyboard layouts leave at least one unread row reachable.
        if (unreadApps.count && unreadHeight < MIN(side, room)) {
            unreadHeight = MIN(side, room);
            height = MIN(height, MAX(0, room - unreadHeight - gap));
        }
        CGFloat total = height + unreadHeight + gap;
        CGFloat bottom = MAX(top + total, MIN(edgeFloor - side - 9 - outsideHeight, anchor + step - side / 2 + padding));
        self.edgeAvailable = available;
        self.resolvedEdgePosition = (bottom - step + side / 2 - padding - top) / MAX(1, available);
        BOOL edgeExpanded = !keyboardUp && (self.edgeUntil > CACurrentMediaTime() ||
            self.rail.dragging || self.rail.decelerating || self.draggingEdge);
        CGFloat x = CGRectGetWidth(bounds) - railWidth + (edgeExpanded ? 0 : NFBRetraction(diameter));
        railFrame = CGRectMake(x, bottom - height, railWidth, height);
        clearCenterY = bottom + 9 + side / 2;
        unreadFrame = CGRectMake(CGRectGetWidth(bounds) - side, bottom - total,
            side + NFBRetraction(diameter), unreadHeight);
    }
    if (actionTarget && actionLandscape && !CGRectIsNull(actionWindowFrame)) {
        // Keep one button inside the landscape window's upper-right corner.
        CGFloat actionSide = MIN((self.iconSize + 14) * 0.75, MIN(actionWindowFrame.size.width, actionWindowFrame.size.height) - 12);
        CGFloat bottomLimit = keyboardUp ? NFBKeyboardTopInView(root) - 12 : CGRectGetHeight(bounds) - MAX(safe.bottom, 6);
        CGFloat x = MAX(6, MIN(CGRectGetMaxX(actionWindowFrame) - actionSide - 6, CGRectGetWidth(bounds) - actionSide - 6));
        CGFloat y = MAX(safe.top + 6, CGRectGetMinY(actionWindowFrame) + 6);
        if (y + actionSide > bottomLimit) y = bottomLimit - actionSide;
        if (actionSide >= 24 && y >= MAX(safe.top, CGRectGetMinY(actionWindowFrame)) &&
            x >= CGRectGetMinX(actionWindowFrame)) topActionFrame = CGRectMake(x, y, actionSide, actionSide);
    }
    [self layoutFavorites:favoritesFrame diameter:diameter active:active duration:layoutDuration];
    [self layoutTopAction:topActionFrame target:actionTarget duration:layoutDuration];
    self.unreadRail.hidden = !edgeMode || !unreadApps.count;
    [UIView animateWithDuration:layoutDuration delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
        animations:^{ self.unreadRail.frame = unreadFrame; } completion:nil];
    self.unreadRail.contentSize = CGSizeMake(CGRectGetWidth(unreadFrame), unreadContentHeight);
    self.unreadRail.alwaysBounceVertical = unreadContentHeight > CGRectGetHeight(unreadFrame);
    if (!self.unreadRail.dragging && !self.unreadRail.decelerating) {
        CGFloat offset = MAX(0, unreadContentHeight - CGRectGetHeight(unreadFrame));
        CGFloat targetOffset = (orderChanged || attachmentChanged) ? offset : MIN(offset, self.unreadRail.contentOffset.y);
        NSUInteger activeUnread = [unreadApps indexOfObject:active ?: @""];
        if (activeUnread != NSNotFound && (orderChanged || attachmentChanged || ![self.lastRailActive isEqual:active] || keyboardUp != previousKeyboardUp))
            targetOffset = NFBRevealOffset(targetOffset, CGRectGetHeight(unreadFrame), unreadContentHeight,
                NFBRowCenter(unreadApps.count, activeUnread, step, side), side);
        [UIView animateWithDuration:layoutDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.unreadRail.contentOffset = CGPointMake(0, targetOffset);
        } completion:nil];
    }
    BOOL railSizeChanged = !CGSizeEqualToSize(self.rail.bounds.size, railFrame.size);
    // Narrow only the visible edge material. Retain the padded hit/clip area
    // so icon edges, shadows and the external unread badges stay intact.
    CGRect materialFrame = edgeMode ? CGRectInset(railFrame, 5, 0) : railFrame;
    self.rail.containerMode = YES;
    self.rail.layer.cornerRadius = MIN(14, railWidth / 4);
    self.rail.alwaysBounceVertical = contentHeight > height;
    self.rail.showsVerticalScrollIndicator = NO;
    if (!CGRectEqualToRect(self.rail.frame, railFrame) || self.railMaterial.alpha != (rowCount && height > 0 ? 0.55 : 0)) {
        if (CGRectIsEmpty(self.rail.frame)) self.rail.frame = railFrame;
        [UIView animateWithDuration:layoutDuration delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
            animations:^{
                self.rail.frame = railFrame;
                self.railMaterial.layer.cornerRadius = MIN(14, railWidth / 4);
                self.railMaterial.frame = materialFrame;
                self.railMaterial.alpha = rowCount && height > 0 ? 0.55 : 0;
            } completion:nil];
    }
    self.rail.contentSize = CGSizeMake(railWidth, contentHeight);
    CGFloat maxOffset = MAX(0, self.rail.contentSize.height - height);
    if (!self.rail.dragging && !self.rail.decelerating) {
        CGFloat offset = attachmentChanged ? maxOffset - oldBottomOffset : self.rail.contentOffset.y;
        offset = MAX(0, MIN(maxOffset, offset));
        NSUInteger activeIndex = [railApps indexOfObject:active ?: @""];
        if (activeIndex != NSNotFound && (attachmentChanged || orderChanged ||
                ![self.lastRailActive isEqual:active] || keyboardUp != previousKeyboardUp || railSizeChanged))
            offset = NFBRevealOffset(offset, height, contentHeight, NFBRowCenter(rowCount, activeIndex, step, side), side);
        self.lastRailActive = active;
        [UIView animateWithDuration:layoutDuration delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
            animations:^{ self.rail.contentOffset = CGPointMake(0, offset); } completion:nil];
    }
    [displayApps enumerateObjectsUsingBlock:^(NSString *appID, __unused NSUInteger index, __unused BOOL *stop) {
        BOOL isClearAll = [appID isEqualToString:NFBClearAllID];
        BOOL isStorage = [appID isEqualToString:NFBStorageID];
        BOOL isFullscreen = [appID isEqualToString:fullscreenApp];
        BOOL isOutside = edgeMode && [unreadApps containsObject:appID];
        NSUInteger rowIndex = isOutside ? [unreadApps indexOfObject:appID] : [railApps indexOfObject:appID];
        UIView *parent = (isClearAll || isStorage || isFullscreen) ? root : (isOutside ? self.unreadRail : self.rail);
        NFBBubble *button = self.buttons[appID];
        BOOL fresh = !button;
        if (fresh) {
            button = [[NFBBubble alloc] initWithFrame:CGRectZero];
            button.appID = appID;
            if (isStorage) {
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(storageTapped:)];
                UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(storageLongPressed:)];
                hold.minimumPressDuration = 0.45;
                [tap requireGestureRecognizerToFail:hold];
                [button addGestureRecognizer:hold];
                [button addGestureRecognizer:tap];
            } else if (isClearAll) {
                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(clearAllTapped:)];
                tap.numberOfTapsRequired = 1;
                UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(clearAllHeld:)];
                hold.minimumPressDuration = 0.5;
                [tap requireGestureRecognizerToFail:hold];
                [button addGestureRecognizer:hold];
                [button addGestureRecognizer:tap];
            } else {
                UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapped:)];
                singleTap.delegate = self;
                UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(edgeLongPressed:)];
                hold.minimumPressDuration = 0.45;
                hold.cancelsTouchesInView = YES;
                hold.delegate = self;
                [singleTap requireGestureRecognizerToFail:hold];
                [self.edgeTap requireGestureRecognizerToFail:hold];
                [button addGestureRecognizer:singleTap];
                [button addGestureRecognizer:hold];
            }
            self.buttons[appID] = button;
            [parent addSubview:button];
        }
        if (button.superview != parent) {
            // Preserve screen position when moving between unread strip and rail.
            CGPoint position = [button.superview convertPoint:button.center toView:parent];
            [parent addSubview:button];
            button.center = position;
        }
        if (isStorage) [self styleStorageButton:button count:storedCount];
        else if (isClearAll) {
            [self styleClearAllButton:button];

        }
        else [self updateBubble:button record:[self.store latestForApp:appID]];
        if (!isOutside && !isClearAll && !isStorage) {
            CGFloat badgeHeight = MIN(16, diameter * 0.5);
            CGFloat badgeWidth = MIN(diameter, MAX(badgeHeight, CGRectGetWidth(button.badge.frame) * 0.8));
            button.badge.frame = CGRectMake(7, 7, badgeWidth, badgeHeight);
            button.badge.layer.cornerRadius = badgeHeight / 2;
            button.badge.font = [UIFont boldSystemFontOfSize:MIN(11, badgeHeight * 0.7)];
            button.badge.adjustsFontSizeToFitWidth = YES;
            button.badge.minimumScaleFactor = 0.65;
        }
        // A bubble we already started retracting must not be re-expanded by the
        // stale "window still visible" reading taken mid-transition.
        [button updateActiveMark:(!isStorage && !isClearAll && ([active isEqualToString:appID] || isFullscreen))
            diameter:diameter duration:layoutDuration];
        BOOL retracting = [self.retracting containsObject:appID];
        // "Has unread" is now the store's unread count, not a short timer: a
        // bubble with any pending notification stays fully visible (never folds)
        // until the record is consumed by opening the app.
        BOOL hasUnread = [self.store countForApp:appID] > 0;
        // With an app sitting in the TrollOpen split view every bubble stays out
        // instead of only that app's, so the whole row is reachable at a glance.
        // Edge read icons move with their container. Only external unread icons
        // use independent reveal/retraction timers.
        BOOL expanded = !keyboardUp && !retracting && (floatingApp.length > 0 || [self.expandedUntil[appID] doubleValue] > CACurrentMediaTime());
        (void)hasUnread;
        CGFloat retraction = isOutside && !expanded ? NFBRetraction(diameter) : 0;
        CGAffineTransform target = CGAffineTransformMakeTranslation(retraction, 0);
        CGRect targetBounds = CGRectMake(0, 0, side, side);
        // Keep the same bottom-first app ordering on desktop and in split view.
        // The clear action is appended last and therefore stays above all apps.
        CGFloat rowY = (isClearAll || isStorage || isFullscreen) ? side / 2 : NFBRowCenter(isOutside ? unreadApps.count : rowCount, rowIndex, step, side);
        CGFloat corner = !isOutside && !isClearAll ? diameter * 0.23 : diameter / 2;
        CGPoint targetCenter = (isClearAll || isStorage) ? CGPointMake(CGRectGetMidX(railFrame), clearCenterY)
            : (isFullscreen ? CGPointMake(CGRectGetWidth(bounds) - side / 2, clearCenterY + side + 9) : CGPointMake(side / 2, rowY));
        if (fresh) {
            button.bounds = targetBounds;
            button.center = targetCenter;
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = corner;
            button.transform = CGAffineTransformMakeTranslation(side + 10, 0);
            button.alpha = 0;
        }
        // The clear-all bubble is an action, not an app: keep it fully opaque so
        // it stays discoverable, unlike the dimmed background bubbles around it.
        CGFloat alpha = self.iconOpacity;
        if (isClearAll || isStorage) {
            alpha = 1.0;
        } else if (isFullscreen || [active isEqualToString:appID]) {
            alpha = 1.0;
        }
        // A bubble mid-shake (fresh notification during split view) stays fully
        // opaque for the reminder's duration, whatever its normal state is.
        if (!containerMode && [self.shakingApps containsObject:appID]) alpha = 1.0;
        BOOL changed = fresh || fabs(button.imageView.layer.cornerRadius - corner) > 0.01 || !CGRectEqualToRect(button.bounds, targetBounds) ||
            !CGPointEqualToPoint(button.center, targetCenter) ||
            !CGAffineTransformEqualToTransform(button.transform, target) ||
            fabs(button.alpha - alpha) > 0.001;
        if (changed) {
            [UIView animateWithDuration:layoutDuration
                delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0
                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                animations:^{
                    // Bounds/center remain valid even while the view is transformed.
                    button.bounds = targetBounds;
                    button.center = targetCenter;
                    button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
                    button.imageView.layer.cornerRadius = corner;
                    button.transform = target;
                    button.alpha = alpha;
                } completion:nil];
        }
    }];
    [self layoutEdgeCopies:railApps unread:unreadApps diameter:diameter active:active duration:layoutDuration];
}
- (void)layoutEdgeCopies:(NSArray<NSString *> *)apps unread:(NSArray<NSString *> *)unread diameter:(CGFloat)diameter active:(NSString *)active duration:(NSTimeInterval)duration {
    if (!self.edgeCopies) self.edgeCopies = [NSMutableDictionary dictionary];
    NSMutableArray *wanted = [NSMutableArray array];
    if (self.edgeMode) for (NSString *app in apps) if ([unread containsObject:app]) [wanted addObject:app];
    for (NSString *app in self.edgeCopies.allKeys) if (![wanted containsObject:app]) {
        NFBBubble *old = self.edgeCopies[app]; [self.edgeCopies removeObjectForKey:app];
        old.userInteractionEnabled = NO;
        if ([self.closingApps containsObject:app]) { [self burstBubble:old]; [old removeFromSuperview]; }
        else [UIView animateWithDuration:duration animations:^{ old.alpha = 0; } completion:^(__unused BOOL done) { [old removeFromSuperview]; }];
    }
    CGFloat side = diameter + 14, step = diameter + 9;
    for (NSString *app in wanted) {
        NFBBubble *button = self.edgeCopies[app];
        if (!button) {
            button = [[NFBBubble alloc] initWithFrame:CGRectMake(0, 0, side, side)]; button.appID = app;
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapped:)];
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(edgeLongPressed:)];
            hold.minimumPressDuration = 0.45; hold.delegate = self; tap.delegate = self;
            [tap requireGestureRecognizerToFail:hold]; [self.edgeTap requireGestureRecognizerToFail:hold];
            [button addGestureRecognizer:tap]; [button addGestureRecognizer:hold];
            self.edgeCopies[app] = button; [self.rail addSubview:button]; button.alpha = 0;
        }
        [self updateBubble:button record:[self.store latestForApp:app]];
        [button updateActiveMark:[app isEqual:active] diameter:diameter duration:duration];
        CGFloat badgeHeight = MIN(16, diameter * 0.5);
        button.badge.frame = CGRectMake(7, 7, MIN(diameter, 24), badgeHeight);
        button.badge.layer.cornerRadius = badgeHeight / 2;
        button.badge.font = [UIFont boldSystemFontOfSize:MIN(11, badgeHeight * 0.7)];
        button.badge.adjustsFontSizeToFitWidth = YES;
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            button.bounds = CGRectMake(0, 0, side, side);
            button.center = CGPointMake(side/2, NFBRowCenter(apps.count, [apps indexOfObject:app], step, side));
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = diameter * 0.23;
            button.alpha = [app isEqual:active] ? 1 : self.iconOpacity;
        } completion:nil];
    }
}
- (void)layoutFavorites:(CGRect)frame diameter:(CGFloat)diameter active:(NSString *)active duration:(NSTimeInterval)duration {
    UIView *root = self.window.rootViewController.view;
    if (!self.favoritesRail) {
        self.favoriteButtons = [NSMutableDictionary dictionary];
        self.favoritesRail = [NFBRail new];
        self.favoritesRail.containerMode = YES;
        self.favoritesRail.delegate = self;
        self.favoriteHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(favoriteHeld:)];
        self.favoriteHold.minimumPressDuration = 0.45;
        [self.favoritesRail addGestureRecognizer:self.favoriteHold];
        self.favoritesRail.clipsToBounds = YES;
        self.favoritesRail.showsVerticalScrollIndicator = NO;
        self.favoritesRail.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.favoritesMaterial = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        self.favoritesMaterial.userInteractionEnabled = NO;
        self.favoritesMaterial.clipsToBounds = YES;
        [root addSubview:self.favoritesMaterial];
        [root addSubview:self.favoritesRail];
    }
    BOOL visible = !self.edgeMode && self.favoriteApps.count && frame.size.height > 0;
    if (!visible && self.favoritesRail.userInteractionEnabled) {
        [self saveFavoritePosition];
        [self finishFavoriteDrag];
    }
    self.favoritesRail.userInteractionEnabled = visible;
    CGFloat side = diameter + 14, step = diameter + 9;
    CGFloat oldBottomDistance = MAX(0, self.favoritesRail.contentSize.height - self.favoritesRail.bounds.size.height - self.favoritesRail.contentOffset.y);
    BOOL wasHidden = self.favoritesRail.alpha < 0.01 || CGRectIsEmpty(self.favoritesRail.frame);
    BOOL resized = !CGSizeEqualToSize(self.favoritesRail.bounds.size, frame.size);
    if (wasHidden && visible) { self.favoritesRail.frame = frame; self.favoritesMaterial.frame = frame; }
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (visible) { self.favoritesRail.frame = frame; self.favoritesMaterial.frame = frame; }
        self.favoritesRail.alpha = visible ? 1 : 0;
        self.favoritesMaterial.alpha = visible ? 0.55 : 0;
        self.favoritesRail.layer.cornerRadius = MIN(14, side / 4);
        self.favoritesMaterial.layer.cornerRadius = MIN(14, side / 4);
    } completion:nil];
    for (NSString *app in self.favoriteButtons.allKeys) if (![self.favoriteApps containsObject:app]) {
        [self.favoriteButtons[app] removeFromSuperview]; [self.favoriteButtons removeObjectForKey:app];
    }
    CGFloat content = self.favoriteApps.count ? (self.favoriteApps.count - 1) * step + side : 0;
    CGFloat maxOffset = MAX(0, content - frame.size.height);
    self.favoritesRail.contentSize = CGSizeMake(side, content);
    self.favoritesRail.alwaysBounceVertical = content > frame.size.height;
    if (!self.favoriteDrag && !self.favoritesRail.dragging && !self.favoritesRail.decelerating && visible) {
        CGFloat offset = MAX(0, MIN(maxOffset, maxOffset - (wasHidden ? MAX(0, NFBNumber(@"FavoriteScrollRows", 0)) * step : oldBottomDistance)));
        NSUInteger activeIndex = [self.favoriteApps indexOfObject:active ?: @""];
        if (activeIndex != NSNotFound && (wasHidden || resized || ![self.lastFavoritesActive isEqual:active]))
            offset = NFBRevealOffset(offset, frame.size.height, content,
                NFBRowCenter(self.favoriteApps.count, activeIndex, step, side), side);
        self.lastFavoritesActive = active;
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.favoritesRail.contentOffset = CGPointMake(0, offset);
        } completion:nil];
    }
    [self.favoriteApps enumerateObjectsUsingBlock:^(NSString *app, NSUInteger index, __unused BOOL *stop) {
        NFBBubble *button = self.favoriteButtons[app];
        if (!button) {
            button = [[NFBBubble alloc] initWithFrame:CGRectMake(0, 0, side, side)]; button.appID = app;
            [button addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapped:)]];
            self.favoriteButtons[app] = button; [self.favoritesRail addSubview:button];
        }
        [self updateBubble:button record:[self.store latestForApp:app]];
        [button updateActiveMark:[app isEqual:active] diameter:diameter duration:duration];
        CGFloat badgeHeight = MIN(16, diameter * 0.5);
        button.badge.frame = CGRectMake(7, 7, MIN(diameter, 24), badgeHeight);
        button.badge.layer.cornerRadius = badgeHeight / 2;
        button.badge.font = [UIFont boldSystemFontOfSize:MIN(11, badgeHeight * 0.7)];
        button.badge.adjustsFontSizeToFitWidth = YES; button.badge.minimumScaleFactor = 0.65;
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            button.bounds = CGRectMake(0, 0, side, side);
            if (button != self.favoriteDrag) button.center = CGPointMake(side / 2, NFBRowCenter(self.favoriteApps.count, index, step, side));
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = diameter * 0.23;
            button.alpha = [app isEqual:active] ? 1 : self.iconOpacity;
        } completion:nil];
    }];
}
- (void)saveFavoritePosition {
    if (!self.favoritesRail || self.favoritesRail.alpha < 0.01) return;
    CGFloat step = MAX(1, self.favoritesRail.contentSize.width - 5);
    CGFloat distance = MAX(0, self.favoritesRail.contentSize.height - self.favoritesRail.bounds.size.height - self.favoritesRail.contentOffset.y);
    CFPreferencesSetAppValue(CFSTR("FavoriteScrollRows"), (__bridge CFPropertyListRef)@(distance / step), NFBDomain);
    CFPreferencesAppSynchronize(NFBDomain);
}
- (void)finishFavoriteDrag {
    [self.favoriteDragTimer invalidate]; self.favoriteDragTimer = nil;
    if (!self.favoriteDrag) return;
    self.favoriteDrag.layer.zPosition = 0;
    self.favoriteDrag = nil;
    self.favoritesRail.scrollEnabled = YES;
    CFPreferencesSetAppValue(CFSTR("FavoriteOrder"), (__bridge CFPropertyListRef)self.favoriteApps, NFBDomain);
    CFPreferencesAppSynchronize(NFBDomain);
    [self saveFavoritePosition];
}
- (void)favoriteHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([self isLocked] || self.edgeMode || !self.enabled) return;
        CGPoint point = [gesture locationInView:self.favoritesRail];
        for (NFBBubble *button in self.favoriteButtons.allValues) {
            if (CGRectContainsPoint(button.frame, point)) { self.favoriteDrag = button; break; }
        }
        if (!self.favoriteDrag) return;
        self.favoriteGrabOffset = point.y - self.favoriteDrag.center.y;
        self.favoritesRail.scrollEnabled = NO;
        self.favoriteDrag.layer.zPosition = 10;
        __weak typeof(self) weakSelf = self;
        self.favoriteDragTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf moveFavorite]; }];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        [self moveFavorite];
    } else {
        [self finishFavoriteDrag]; [self refresh];
    }
}
- (void)moveFavorite {
    NFBBubble *button = self.favoriteDrag;
    if (!button) return;
    if ([self isLocked] || self.edgeMode || !self.enabled || ![self.favoriteApps containsObject:button.appID]) {
        [self finishFavoriteDrag]; return;
    }
    UIScrollView *rail = self.favoritesRail;
    CGPoint point = [self.favoriteHold locationInView:rail];
    CGFloat localY = point.y - rail.contentOffset.y;
    CGFloat delta = localY < 28 ? -4 : (localY > rail.bounds.size.height - 28 ? 4 : 0);
    CGFloat maxOffset = MAX(0, rail.contentSize.height - rail.bounds.size.height);
    rail.contentOffset = CGPointMake(0, MAX(0, MIN(maxOffset, rail.contentOffset.y + delta)));
    point = [self.favoriteHold locationInView:rail];
    CGFloat side = rail.contentSize.width, step = MAX(1, side - 5);
    CGFloat y = MAX(side/2, MIN(rail.contentSize.height - side/2, point.y - self.favoriteGrabOffset));
    [button.layer removeAllAnimations]; button.center = CGPointMake(side/2, y);
    NSInteger row = (NSInteger)llround((y - side/2) / step);
    NSUInteger destination = self.favoriteApps.count - 1 - MIN(self.favoriteApps.count - 1, (NSUInteger)MAX(0, row));
    NSUInteger source = [self.favoriteApps indexOfObject:button.appID];
    if (source != destination && source != NSNotFound) {
        NSMutableArray *apps = [self.favoriteApps mutableCopy];
        [apps removeObjectAtIndex:source]; [apps insertObject:button.appID atIndex:destination];
        self.favoriteApps = apps;
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            [apps enumerateObjectsUsingBlock:^(NSString *app, NSUInteger i, __unused BOOL *stop) {
                NFBBubble *other = self.favoriteButtons[app];
                if (other != button) other.center = CGPointMake(side/2, NFBRowCenter(apps.count, i, step, side));
            }];
        } completion:nil];
    }
}
// One action per gesture. Without this, a bounce in the finger or a leftover
// second tap of a retired double-tap would fire close/exit twice in a row.
- (BOOL)acceptGesture {
    NSTimeInterval now = CACurrentMediaTime();
    if (now - self.lastGestureAt < NFBGestureCooldown) return NO;
    self.lastGestureAt = now;
    // While the folded stack is spread open, any tap keeps it open for another
    // NFBStackHold seconds — only 4 seconds of no action folds it back.
    if (self.edgeMode) [self restartStorageIdleTimer];
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
- (void)closeBubble:(NFBBubble *)button {
    if (self.buttons[button.appID] != button && self.edgeCopies[button.appID] != button) return;
    if (![self acceptGesture]) return;
    NSString *app = button.appID;
    // Suppress touch-up activation while the queued burst removes this control.
    button.opening = YES;
    button.userInteractionEnabled = NO;
    [self.dismissedSwitcher addObject:app];
    [self.closingApps addObject:app];
    [self closeAppsInOrder:@[app]];
    dispatch_async(dispatch_get_main_queue(), ^{
        // If a new notification cancelled dismissal, leave that surviving icon usable.
        if (self.buttons[app] == button || self.edgeCopies[app] == button) {
            button.opening = NO; button.userInteractionEnabled = YES;
        }
    });
    // Let the burst read first, then terminate the process behind it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NFBDebugLog(@"gesture: long press on app %@ -> terminate", app);
        NFBTerminateApp(app);
        [self refresh];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.closingApps removeObject:app];
        });
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
    button.accessibilityLabel = [NSString stringWithFormat:self.backgroundCollapsed ? @"已收纳 %lu 个无未读应用" : @"可收纳 %lu 个无未读应用", (unsigned long)count];
    button.accessibilityHint = @"点击收起或展开后台图标，长按上下拖动位置";
}
- (void)storageLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (!self.edgeMode || self.buttons[NFBStorageID] != gesture.view) return;
    ((NFBBubble *)gesture.view).holdStartedRetracted = YES;
    [self restartStorageIdleTimer];
    [self edgeLongPressed:gesture];
}
- (void)storageTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || ![self acceptGesture]) return;
    self.backgroundCollapsed = !self.backgroundCollapsed;
    if (!self.backgroundCollapsed) {
        [self restartStorageIdleTimer];
        [self extendEdgeContainer];
    } else self.stackUntil = 0;
    [self refresh];
}
- (void)restartStorageIdleTimer {
    if (self.backgroundCollapsed) { self.stackUntil = 0; return; }
    self.stackUntil = CACurrentMediaTime() + NFBStackHold;
    NSTimeInterval deadline = self.stackUntil;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NFBStackHold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) owner = weakSelf;
        if (!owner || owner.stackUntil != deadline || owner.backgroundCollapsed) return;
        if (owner.draggingEdge || owner.rail.tracking || owner.rail.dragging || owner.rail.decelerating) {
            [owner restartStorageIdleTimer];
            return;
        }
        owner.stackUntil = 0;
        owner.backgroundCollapsed = YES;
        [owner refresh]; // Unread apps remain visible through NFBVisibleEdgeApps.
    });
}
- (BOOL)edgeBubbleIsRetracted:(NFBBubble *)button {
    if (!self.edgeMode) return NO;
    CALayer *layer = button.imageView.layer.presentationLayer ?: button.imageView.layer;
    CGRect image = [layer convertRect:layer.bounds toLayer:self.window.rootViewController.view.layer];
    return CGRectGetMaxX(image) > CGRectGetWidth(self.window.rootViewController.view.bounds) + 0.5;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture == self.topActionTap) {
        self.topActionTouchTarget = self.topActionTarget;
        return self.enabled && ![self isLocked] && self.topActionTouchTarget != nil;
    }
    if (gesture == self.edgeTap) {
        // Bubble taps handle their own reveal. Do not race them with a parent tap.
        for (UIView *view = touch.view; view && view != self.rail; view = view.superview)
            if ([view isKindOfClass:NFBBubble.class]) return NO;
        return YES;
    }
    if (![gesture.view isKindOfClass:NFBBubble.class]) return YES;
    NFBBubble *button = (NFBBubble *)gesture.view;
    BOOL tucked = [self edgeBubbleIsRetracted:button];
    if ([gesture isKindOfClass:UILongPressGestureRecognizer.class]) button.holdStartedRetracted = tucked;
    // Freeze the interaction decision at touch-down; a one-second timer must
    // not turn a held expanded icon into a drag into a drag after its timer expires.
    if (self.edgeMode) [self restartStorageIdleTimer];
    if (self.edgeMode && !tucked) {
        if (button.superview == self.rail) [self extendEdgeContainer];
        else [self extendApp:button.appID];
    }
    return YES;
}
- (void)edgeLongPressed:(UILongPressGestureRecognizer *)gesture {
    UIView *root = self.window.rootViewController.view;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NFBBubble *button = (NFBBubble *)gesture.view;
        if (!self.edgeMode || !button.holdStartedRetracted) {
            [self closeBubble:button];
            return;
        }
        self.draggingEdge = YES;
        self.dragStartY = [gesture locationInView:root].y;
        self.dragSavedPosition = self.verticalPosition;
        self.dragStartPosition = self.resolvedEdgePosition;
        self.rail.scrollEnabled = NO;
        self.unreadRail.scrollEnabled = NO;
        [self extendEdgeContainer];
    }
    if (!self.draggingEdge) return;
    if (!self.edgeMode || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        self.verticalPosition = self.dragSavedPosition;
        self.draggingEdge = NO;
    } else if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateEnded) {
        CGFloat delta = [gesture locationInView:root].y - self.dragStartY;
        self.verticalPosition = NFBPosition(self.dragStartPosition + delta / MAX(1, self.edgeAvailable));
        if (gesture.state == UIGestureRecognizerStateEnded) {
            self.draggingEdge = NO;
            CFPreferencesSetAppValue(CFSTR("EdgeVerticalPosition"), (__bridge CFPropertyListRef)@(self.verticalPosition), NFBDomain);
            CFPreferencesAppSynchronize(NFBDomain);
        }
    }
    if (!self.draggingEdge) {
        self.rail.scrollEnabled = YES;
        self.unreadRail.scrollEnabled = YES;
        [self extendEdgeContainer];
    }
    [self refresh];
}
- (void)extendEdgeContainer {
    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0 : NFBMotion;
    self.edgeUntil = CACurrentMediaTime() + duration + NFBHold;
    NSTimeInterval deadline = self.edgeUntil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((duration + NFBHold) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.edgeUntil == deadline) [self refresh];
    });
}
- (void)edgeContainerTapped:(UITapGestureRecognizer *)gesture {
    if (!self.edgeMode || gesture.state != UIGestureRecognizerStateEnded) return;
    [self restartStorageIdleTimer];
    [self extendEdgeContainer];
    [self refresh];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return [gesture isKindOfClass:UITapGestureRecognizer.class] &&
        [other isKindOfClass:UITapGestureRecognizer.class] &&
        (gesture == self.edgeTap || other == self.edgeTap);
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView != self.rail || !self.edgeMode) return;
    [self restartStorageIdleTimer];
    [self extendEdgeContainer]; [self refresh];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == self.favoritesRail && !decelerate) [self saveFavoritePosition];
    if (scrollView != self.rail || !self.edgeMode || decelerate) return;
    [self restartStorageIdleTimer];
    [self extendEdgeContainer]; [self refresh];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.favoritesRail) [self saveFavoritePosition];
    if (scrollView != self.rail || !self.edgeMode) return;
    [self restartStorageIdleTimer];
    [self extendEdgeContainer]; [self refresh];
}
- (void)singleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    [self tapped:button];
}
- (void)tapped:(NFBBubble *)button {
    if (button.opening || (self.buttons[button.appID] != button && self.favoriteButtons[button.appID] != button && self.edgeCopies[button.appID] != button)) return;
    if (self.pendingRecord && [self.pendingRecord.appID isEqual:button.appID]) return;
    if (![self acceptGesture]) return;
    button.opening = YES;
    if (self.edgeMode && button.superview == self.rail) [self extendEdgeContainer];
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
    NFBResetSplitPlacement();
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
