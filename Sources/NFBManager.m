#import "NFBRailScrolling.h"
#import "NFBDesktopHost.h"
#import "NFBHotspot.h"
#import "NFBSystemDesktop.h"
#import "NFBOpenConsole.h"
#import "NFBWindowState.h"
#import "NFBTransitionPolicy.h"
#import "NFBIcon.h"
#import "NFBManager.h"
#import "NFBPrivate.h"
#import "NFBStore.h"
#import "NFBGeometry.h"
#import "NFBSwitcher.h"
#import "NFBTrollOpen.h"
#import "NFBWindowControls.h"
#import "NFBOpenEdge.h"
#import "NFBNotificationPolicy.h"
#import "NFBAppExit.h"
#import "NFBKeyboard.h"
#import "NFBDebugLog.h"
#import "NFBEdgeInspection.h"
#import "NFBEdgeLayout.h"
#import "NFBPrivacy.h"
#import "NFBContainerLayout.h"

static const NSTimeInterval NFBMotion = 0.35;
// No double-tap recognizer: a short tap resolves on release.
// Guard against repeated callbacks from the same completed gesture.
static const NSTimeInterval NFBGestureCooldown = 0.25;

// Vertical position (0 = top, 1 = bottom) the whole row shifts to while an app
// is in the split view, so it clears the floating window. Restores on exit.
static const CGFloat NFBFloatingPosition = 0.80;
// Vertical position the row shifts to while the keyboard is up, so the bubbles
// clear the keyboard. Applies in BOTH split view and fullscreen, and outranks
// every other position rule.
static const CGFloat NFBKeyboardPosition = 0.49;
// Synthetic bubble id that rides at the top of the row while an app is in the
// split view. Tapping it clears every background app at once. It never enters
// the store or the switcher ordering.
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

// Both active rails are ordinary interactive scroll containers.
@interface NFBRail : UIScrollView @end
@implementation NFBRail @end

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
@property(nonatomic, copy) void (^tapHandler)(void);
@property(nonatomic, strong) UILabel *badge;
@property(nonatomic, strong) UIView *activeMark;
- (void)updateActiveMark:(BOOL)active diameter:(CGFloat)diameter duration:(NSTimeInterval)duration;
@property(nonatomic) BOOL opening;
@end
@implementation NFBBubble
// UIControl without target-actions returns NO here, which made every bubble
// inert to VoiceOver's double-tap. tapHandler is installed alongside the tap
// gesture so both input paths run the same code.
- (BOOL)accessibilityActivate {
    if (!self.tapHandler) return [super accessibilityActivate];
    self.tapHandler();
    return YES;
}
// Pressed-state feedback; the views previously had none.
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{
            self.imageView.transform = highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
            self.imageView.alpha = highlighted ? 0.85 : 1.0;
        } completion:nil];
}
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
        _badge.autoresizingMask = UIViewAutoresizingNone;
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
        // The visible shape is the circular imageView; without an oval path the
        // shadow traced this square bounds and showed as a halo behind the icon.
        self.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(7, 7, 48, 48)].CGPath;
    }
    return self;
}
@end

@interface NFBManager () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) NFBStore *store;
@property(nonatomic, strong) NFBWindow *window;
@property(nonatomic, strong) NFBRail *rail;

@property(nonatomic, strong) NFBBubble *desktopActionButton;
@property(nonatomic, strong) UITapGestureRecognizer *desktopActionTap;
@property(nonatomic, strong) UILongPressGestureRecognizer *desktopActionHold;
@property(nonatomic, weak) UIView *desktopActionTarget;
@property(nonatomic, weak) UIView *desktopActionTouchTarget;
@property(nonatomic, weak) UIView *observedActionTarget;
@property(nonatomic) CGRect observedActionFrame;
- (void)desktopActionTapped:(UITapGestureRecognizer *)gesture;
- (void)layoutDesktopAction:(CGRect)frame target:(UIView *)target duration:(NSTimeInterval)duration;

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
- (void)favoriteTapped:(UITapGestureRecognizer *)gesture;
- (void)saveFavoritePosition;
- (void)layoutBadge:(NFBBubble *)button diameter:(CGFloat)diameter;
- (void)schedulePreferenceFlush;
@property(nonatomic, copy) NSString *lastRailActive;
@property(nonatomic, copy) NSString *lastFavoritesActive;
- (void)clearAllHeld:(UILongPressGestureRecognizer *)gesture;
- (void)layoutFavorites:(CGRect)frame diameter:(CGFloat)diameter active:(NSString *)active duration:(NSTimeInterval)duration;

@property(nonatomic) BOOL edgeMode;
- (void)closeBubble:(NFBBubble *)button;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *buttons;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *imageRetryAfter;
@property(nonatomic, strong) NSMutableSet<NSString *> *burstApps;
@property(nonatomic, strong) NSArray<NSString *> *lastSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *dismissedSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *closingApps;
@property(nonatomic) NSUInteger exitEpoch;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *retractTokens;
@property(nonatomic) NSUInteger presentationEpoch;
@property(nonatomic) BOOL closePreviousSplit, hideInScreenshots;
@property(nonatomic) BOOL refreshScheduled;
@property(nonatomic) BOOL columnSliding;
@property(nonatomic) BOOL columnTargetOffscreen;
@property(nonatomic) BOOL preferenceFlushPending;
@property(nonatomic, strong) UILabel *noticeLabel;
@property(nonatomic) NSUInteger noticeToken;
@property(nonatomic) CGFloat favoriteScrollRows;
@property(nonatomic) BOOL favoriteDragConsumed;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *generations;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastBadges;
@property(nonatomic, strong) NFBRecord *pendingRecord;
@property(nonatomic) NSTimeInterval pendingUntil;
@property(nonatomic) NSUInteger emptyReads;
@property(nonatomic) CGFloat verticalPosition;
@property(nonatomic, copy) NSString *lastActiveApp;
@property(nonatomic, strong) NSMutableArray<NSString *> *recentUsedApps;
@property(nonatomic, copy) NSArray *lastLayoutApps;
@property(nonatomic) CGFloat iconSize;
@property(nonatomic) CGFloat iconOpacity;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL showLock;
@property(nonatomic) BOOL showHome;
@property(nonatomic) BOOL showApps;
@property(nonatomic) NSTimeInterval lastGestureAt;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *gestureTimes;
// Until when the folded (no-unread) bubbles stay spread out after a tap. When
// in the past, they fold back into a thin stack at the bottom edge.
// Apps whose bubble is already retracting because we asked TrollOpen to end the
// floating window. Marking them lets the retract animation start on the same
// frame as the window transition instead of waiting for the window to be gone.
@property(nonatomic, strong) NSMutableSet<NSString *> *retracting;
// High-frequency watcher that only runs while a floating window exists, so a
// window dismissed outside the plugin (TrollOpen's own bar, app crash, exit) is
// picked up in ~one frame rather than on the next 0.5s poll.
@property(nonatomic, strong) NSTimer *floatingWatch;
@property(nonatomic) CGRect observedSplitFrame;
@property(nonatomic) CGRect lastSplitFrame;
@property(nonatomic) BOOL splitRailActive;
@property(nonatomic) CGFloat splitRailDiameter;
@property(nonatomic, strong) UIVisualEffectView *railMaterial;
@property(nonatomic, copy) NSString *watchedFloating;
// Previous keyboard state, so refresh can spot the up/down edges.
@property(nonatomic) BOOL keyboardUp;
- (void)refresh;
- (void)setColumnOffscreen:(BOOL)offscreen;
- (void)setNeedsRefresh;
- (void)updatePrivacy;
- (void)beginRetracting:(NSString *)app;
- (void)syncFloatingWatch:(NSString *)floating;
- (void)floatingWatchFired;
- (void)floatingWatchBody;
- (BOOL)acceptGesture;
- (BOOL)acceptGestureForKey:(NSString *)key;
- (void)burstBubble:(NFBBubble *)button;
- (BOOL)executeRecord:(NFBRecord *)record;
- (BOOL)executeRecord:(NFBRecord *)record authentication:(BOOL)authentication;
- (void)tick;
- (void)tickBody;
- (void)startTimer;
- (void)closeAppsInOrder:(NSArray<NSString *> *)apps;
- (void)openApp:(NSString *)app;
- (void)showOpenNotice:(NSString *)message;
- (BOOL)isLocked;
- (void)clearBackground;
- (void)clearAllTapped:(UITapGestureRecognizer *)gesture;
- (void)styleClearAllButton:(NFBBubble *)button;
- (void)shakeBubble:(NFBBubble *)button;
- (void)appHeld:(UILongPressGestureRecognizer *)gesture;
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
        _icons = [NSCache new]; _icons.countLimit = 128;
        _imageRetryAfter=[NSMutableDictionary dictionary];
        _burstApps = [NSMutableSet set];
        _retracting = [NSMutableSet set];
        _dismissedSwitcher = [NSMutableSet set];
        _closingApps = [NSMutableSet set];
        _generations = [NSMutableDictionary dictionary];
        _lastBadges = [NSMutableDictionary dictionary];
        _gestureTimes = [NSMutableDictionary dictionary];
        _retractTokens=[NSMutableDictionary dictionary];
        __weak NFBManager *weakSelf = self;
        NFBKeyboardInstall(^{ [weakSelf setNeedsRefresh]; });
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
    BOOL nextEnabled = NFBPreference(@"Enabled", YES);
    if (self.enabled != nextEnabled) { ++self.exitEpoch; ++self.presentationEpoch; }
    self.enabled = nextEnabled;
    NFBConfigureDebugLogging(NFBPreference(@"DebugLogging", NO));
    self.closePreviousSplit = NFBPreference(@"ClosePreviousSplit", YES);
    self.hideInScreenshots = NFBPreference(@"HideInScreenshots", NO);
    self.favoriteScrollRows = NFBNumber(@"FavoriteScrollRows", 0);
    NFBConfigureHotspotAutoClose(self.enabled && NFBPreference(@"HotspotAutoClose",NO),NFBNumber(@"HotspotIdleMinutes",5));
    NFBUpdateOpenEdge(self.enabled);
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
        NFBCloseDesktopSplit();
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
    if ([image isKindOfClass:UIImage.class]) [self.icons setObject:image forKey:appID];
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
    if (appID && notificationID) [self.store removeApp:appID notification:notificationID revision:(NFBRevisionForRequest(request) ?: @"undated")];
    // Release a parked locked-screen tap for this app, otherwise tapped: keeps
    // early-returning on it for the whole pending timeout.
    if (self.pendingRecord && [self.pendingRecord.appID isEqual:appID] &&
        (!notificationID || !self.pendingRecord.notificationID ||
         [self.pendingRecord.notificationID isEqual:notificationID])) {
        self.pendingRecord = nil;
    }
    [self setNeedsRefresh];
}
- (void)removeSection:(NSString *)section {
    [self.store removeApp:section]; [self setNeedsRefresh];
}
- (NSArray<NSString *> *)orderedAppsForRemoval {
    NSMutableOrderedSet *apps = [NSMutableOrderedSet orderedSetWithArray:self.lastLayoutApps ?: @[]];
    [apps addObjectsFromArray:self.store.appIDs];
    [apps removeObject:NFBClearAllID];
    [apps removeObject:NFBSystemDesktopBundleID];
    return apps.array;
}
- (void)clear {
    [self.dismissedSwitcher addObjectsFromArray:self.lastSwitcher ?: @[]];
    [self closeAppsInOrder:[self orderedAppsForRemoval]];
}
// The three-step key path below appeared at five call sites, each allocating two
// selector strings. Resolve the keys once.
static NSString *NFBFrontmostAppID(void) {
    static NSString *frontKey, *bundleKey;
    if (!frontKey) {
        frontKey = @"_accessibilityFrontMostApplication";
        bundleKey = @"bundleIdentifier";
    }
    return NFBString(NFBGet(NFBGet(UIApplication.sharedApplication, frontKey), bundleKey));
}

// "一键清理后台": terminate every app in the switcher/row except the one still
// occupying the floating window, mirroring the long-press exit path but for the
// whole background at once.
- (void)clearBackground {
    NSString *floating = NFBTrollVisibleApp();
    id sb = UIApplication.sharedApplication;
    NSString *front = nil;
    if ([sb respondsToSelector:@selector(isShowingHomescreen)] && ![sb isShowingHomescreen])
        front = NFBFrontmostAppID();
    NSMutableArray<NSString *> *targets = [NSMutableArray array];
    for (NSString *app in [self orderedAppsForRemoval]) {
        if ([app isEqualToString:floating] || [app isEqualToString:front]) continue;
        [targets addObject:app];
    }
    if (!targets.count) return;
    NFBDebugLog(@"gesture: clear-background -> %lu apps", (unsigned long)targets.count);
    [self.dismissedSwitcher addObjectsFromArray:targets];
    [self closeAppsInOrder:targets];
    NSDictionary *exitVersions = [self.generations copy];
    NSUInteger exitEpoch = self.exitEpoch;
    [targets enumerateObjectsUsingBlock:^(NSString *app, __unused NSUInteger index, __unused BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.35 + index * 0.16) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NFBInvalidateWindowState();
            NFBWindowState *state = NFBCurrentWindowState();
            BOOL protected = [app isEqual:state.frontApp] || [app isEqual:state.floatingApp];
            if (NFBExitStillCurrent([exitVersions[app] unsignedIntegerValue], [self.generations[app] unsignedIntegerValue], self.enabled && self.exitEpoch == exitEpoch, NO, protected)) NFBTerminateApp(app);
            [self refresh];
        });
    }];
}
- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.edgeMode || [self isLocked] || ![self acceptGestureForKey:@"closeSplit"]) return;
    NFBCloseDesktopSplit();
    if (!NFBCloseCurrentSplit()) [self showOpenNotice:@"未能读取 TrollOpen 右侧区域的单击接口"];
    else NFBOpenEdgeAfterClose();
    [self refresh];
}
- (void)desktopActionTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !self.enabled || [self isLocked]) return;
    UIView *target = self.desktopActionTouchTarget;
    self.desktopActionTouchTarget = nil;
    if (!target || target != self.desktopActionTarget || target != NFBDesktopActionWindow()) { [self refresh]; return; }
    if (![self acceptGestureForKey:@"desktopAction"]) return;
    if (!NFBShowDesktopInSplit(target)) [self showOpenNotice:NFBDesktopSplitError()];
    [self refresh];
}
- (void)desktopActionHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !self.enabled || [self isLocked]) return;
    UIView *target = self.desktopActionTouchTarget;
    self.desktopActionTouchTarget = nil;
    if (!target || target != self.desktopActionTarget || target != NFBDesktopActionWindow()) { [self refresh]; return; }
    if (![self acceptGestureForKey:@"desktopConsole"]) return;
    NFBCloseDesktopSplit();
    if (!NFBOpenNativeConsole()) [self showOpenNotice:@"Open 控制台入口不可用，请确认使用适配的定制版 1.3.7"];
    [self refresh];
}
- (void)layoutDesktopAction:(CGRect)frame target:(UIView *)target duration:(NSTimeInterval)duration {
    BOOL visible = target && !CGRectIsNull(frame) && !CGRectIsEmpty(frame) && self.enabled;
    self.desktopActionTarget = visible ? target : nil;
    if (!self.desktopActionButton && !visible) return;
    if (!self.desktopActionButton) {
        NFBBubble *button = [[NFBBubble alloc] initWithFrame:frame];
        button.badge.hidden = YES;
        button.imageView.contentMode = UIViewContentModeCenter;
        button.imageView.image = [UIImage systemImageNamed:@"house.fill"];
        button.imageView.tintColor = UIColor.systemGreenColor;
        button.imageView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        button.accessibilityLabel = @"显示桌面 / Open 控制台";
        button.accessibilityHint = @"单击显示或关闭桌面分屏，长按打开 Open 控制台";
        self.desktopActionTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(desktopActionTapped:)];
        self.desktopActionTap.delegate = self;
        self.desktopActionHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(desktopActionHeld:)];
        self.desktopActionHold.minimumPressDuration = 0.45;
        self.desktopActionHold.delegate = self;
        [self.desktopActionTap requireGestureRecognizerToFail:self.desktopActionHold];
        [button addGestureRecognizer:self.desktopActionHold];
        [button addGestureRecognizer:self.desktopActionTap];
        button.alpha = 0;
        self.desktopActionButton = button;
        [self.window.rootViewController.view addSubview:button];
    }
    NFBBubble *button = self.desktopActionButton;
    button.accessibilityLabel = @"显示桌面 / Open 控制台";
    button.accessibilityHint = @"单击显示或关闭桌面分屏，长按打开 Open 控制台";
    CGFloat targetAlpha = visible ? 1 : 0;
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
    if (gesture.state != UIGestureRecognizerStateBegan || [self isLocked] || ![self acceptGestureForKey:@"clearAllHold"]) return;
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
// Restart the native split-container pulse when a new notification arrives.
- (void)shakeBubble:(NFBBubble *)button {
    if (!button.superview || UIAccessibilityIsReduceMotionEnabled()) return;
    CAKeyframeAnimation *pulse=[CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    pulse.values=@[@1,@0.94,@1,@0.97,@1]; pulse.duration=0.65;
    [button.imageView.layer addAnimation:pulse forKey:@"NFBContainerPulse"];
}
- (BOOL)isLocked {
    // Runs several times per refresh on the 20 Hz path; resolve the singleton once.
    static __weak id lockManager;
    static CFTimeInterval retryAt;
    if (!lockManager && CACurrentMediaTime() >= retryAt) {
        lockManager = NFBSingleton(@"SBLockScreenManager");
        retryAt = CACurrentMediaTime() + 5;
    }
    return NFBCheckedBool(lockManager, @"isUILocked", YES);
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
    NSNumber *token=@([self.retractTokens[app] unsignedIntegerValue]+1); self.retractTokens[app]=token;
    [self.retracting addObject:app];
    [self refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![self.retractTokens[app] isEqual:token]) return;
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
    // 20 Hz entry point on the SpringBoard main thread: one uncaught exception
    // from any private call below takes the whole process down.
    @try { [self floatingWatchBody]; }
    @catch (NSException *error) {
        NFBErrorLog(@"floating watch failed: %@", error);
        if (self.floatingWatch) { [self.floatingWatch invalidate]; self.floatingWatch = nil; }
        self.watchedFloating = nil;
    }
}
- (void)floatingWatchBody {
    [self updatePrivacy];
    NFBUpdateOpenEdge(self.enabled);
    NSString *now = NFBSplitAttachmentApp();
    // syncFloatingWatch only keeps this timer alive while an attachment is
    // reported, so there is no idle rate to save here: arriving without one
    // means it was just dismissed, and halving the rate would only delay that.
    NSString *currentApp = NFBTrollVisibleApp();
    // Orientation can change while app identity and window frame stay the same.
    NSString *switchApp = [self.retracting containsObject:currentApp ?: @""] ? nil : currentApp;
    NFBObserveSplitSwitch(switchApp, self.enabled && self.closePreviousSplit);
    CGRect frame = NFBSplitFrameInView(self.window.rootViewController.view);
    BOOL sameFrame = CGRectEqualToRect(frame, self.observedSplitFrame) ||
        (CGRectIsNull(frame) && CGRectIsNull(self.observedSplitFrame));
    UIView *actionTarget = NFBDesktopActionWindow();
    CGRect actionFrame = NFBWindowFrameInView(actionTarget, self.window.rootViewController.view);
    BOOL sameActionFrame = CGRectEqualToRect(actionFrame, self.observedActionFrame) ||
        (CGRectIsNull(actionFrame) && CGRectIsNull(self.observedActionFrame));
    if ((now == self.watchedFloating || [now isEqualToString:self.watchedFloating]) && sameFrame &&
        actionTarget == self.observedActionTarget && sameActionFrame) return;
    self.observedActionTarget = actionTarget; self.observedActionFrame = actionFrame;
    self.observedSplitFrame = frame;
    self.watchedFloating = now;
    [self setNeedsRefresh];
}

- (void)tick {
    if (!self.enabled) return;
    // Same reasoning as floatingWatchFired: private SpringBoard calls here must
    // never propagate out into the runloop.
    @try { [self tickBody]; }
    @catch (NSException *error) { NFBErrorLog(@"tick failed: %@", error); }
}
- (void)tickBody {
    NSString *desktopFailure = NFBConsumeDesktopSplitFailure();
    if (desktopFailure.length) [self showOpenNotice:desktopFailure];
    if (self.pendingRecord) {
        NSString *front = NFBFrontmostAppID();
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
    [self setNeedsRefresh];
}
- (void)closeAppsInOrder:(NSArray<NSString *> *)apps {
    NSDictionary *versions = [self.generations copy];
    NSUInteger epoch=self.exitEpoch;
    [apps enumerateObjectsUsingBlock:^(NSString *app, NSUInteger index, __unused BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(index * 0.16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.exitEpoch!=epoch) return;
            // A notification or reopened switcher card received after this snapshot survives.
            if (self.generations[app] != versions[app] && ![self.generations[app] isEqual:versions[app]]) return;
            [self.burstApps addObject:app];
            [self.store closeApp:app];
            if ([self.pendingRecord.appID isEqual:app]) self.pendingRecord = nil;
            [self refresh];
        });
    }];
}
- (BOOL)shouldShow {
    id lock = NFBSingleton(@"SBLockScreenManager");
    // An unknown lock state must not display an interactive overlay.
    if (!NFBBooleanGetterCompatible(lock, @selector(isUILocked))) return NO;
    if (NFBCheckedBool(lock, @"isUILocked", YES)) return self.showLock;
    id springboard = UIApplication.sharedApplication;
    if (!NFBBooleanGetterCompatible(springboard, @selector(isShowingHomescreen))) return NO;
    return NFBCurrentWindowState().home ? self.showHome : self.showApps;
}
- (void)ensureWindow {
    if (self.window) return;
    UIWindowScene *scene = nil;
    UIWindowScene *fallback = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *candidateScene = (UIWindowScene *)candidate;
        if (candidateScene.activationState == UISceneActivationStateForegroundActive) { scene = candidateScene; break; }
        // A split switch can leave the previously active scene in an inactive
        // state for a moment; binding to a stale scene misplaces every later
        // convertRect:. Keep any foreground-capable scene as a fallback.
        if (!fallback && candidateScene.activationState == UISceneActivationStateForegroundInactive)
            fallback = candidateScene;
    }
    if (!scene) scene = fallback;
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
    self.rail.showsVerticalScrollIndicator = NO;
    self.rail.alwaysBounceVertical = NO;
    self.railMaterial = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    self.railMaterial.userInteractionEnabled = NO;
    self.railMaterial.layer.cornerRadius = 20;
    self.railMaterial.clipsToBounds = YES;
    self.railMaterial.alpha = 0;
    [self.window.rootViewController.view addSubview:self.railMaterial];
    [self.window.rootViewController.view addSubview:self.rail];
    // Never take the key window; keyboard and app focus belong to the system.
}
- (id)iconForApp:(NSString *)appID {
    // The window snapshot object is rebuilt every runloop turn, so keying this
    // cache on it guaranteed a miss and rebuilt the entire dictionary (plus a
    // fresh SBIconController lookup) at 20 Hz. A short time window keeps app
    // installs visible within a second without paying that cost per poll.
    static id model;
    static NSMutableDictionary *objects;
    static CFTimeInterval resolvedAt;
    CFTimeInterval now = CACurrentMediaTime();
    if (!objects || now - resolvedAt > 1.0) {
        objects = [NSMutableDictionary dictionary];
        model = NFBGet(NFBSingleton(@"SBIconController"), @"model");
        resolvedAt = now;
    }
    id cached = objects[appID];
    if (cached) return cached == NSNull.null ? nil : cached;
    NSMethodSignature *signature = NFBSignature(model, @selector(applicationIconForBundleIdentifier:));
    if (!signature || signature.numberOfArguments != 3 || signature.methodReturnType[0] != '@' || [signature getArgumentTypeAtIndex:2][0] != '@') return nil;
    @try { id icon = [model applicationIconForBundleIdentifier:appID]; objects[appID] = icon ?: NSNull.null; return icon; }
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
    // Text only: -layoutBadge:diameter: owns the geometry for all call sites.
    if (![button.badge.text isEqual:text]) button.badge.text = text;
    NSString *name = NFBString(NFBGet(icon, @"displayName")) ?: button.appID;
    NSString *label = [NSString stringWithFormat:@"%@，%@", name, text ?: (record ? @"有通知" : @"暂无新通知")];
    if (![button.accessibilityLabel isEqual:label]) button.accessibilityLabel = label;
    button.accessibilityHint = @"点击打开；长按清除图标及 App";
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
    id image = [self.icons objectForKey:button.appID];
    if (!image && [self.imageRetryAfter[button.appID] doubleValue]<=CACurrentMediaTime()) {
        image = NFBApplicationImage(button.appID, 2, UIScreen.mainScreen.scale);
        if ([image isKindOfClass:UIImage.class]) {
            [self.icons setObject:image forKey:button.appID]; [self.imageRetryAfter removeObjectForKey:button.appID];
        } else {
            if (self.imageRetryAfter.count>=128) [self.imageRetryAfter removeAllObjects];
            self.imageRetryAfter[button.appID]=@(CACurrentMediaTime()+2);
        }
    }
    // Cache the SF Symbol fallback: systemImageNamed: hits the symbol database on
    // every call, and this path runs for apps whose icon lookup failed.
    static UIImage *cachedBell;
    if (!cachedBell) cachedBell = [UIImage systemImageNamed:@"bell.fill"];
    UIImage *resolved=[image isKindOfClass:UIImage.class] ? image : cachedBell;
    // Refreshing counts/window state does not require redisplaying an unchanged icon.
    if (button.imageView.image != resolved) button.imageView.image = resolved;
}
- (void)updatePrivacy {
    if (!self.enabled || [self isLocked]) NFBUpdateDesktopSplit(NO);
    NFBSetCaptureHidden(self.window.rootViewController.view, self.enabled && self.hideInScreenshots);
}
// Coalesced entry point: at most one full layout per runloop turn. Use this for
// notification-driven and timer-driven updates; keep -refresh for gestures that
// need same-frame feedback.
- (void)setNeedsRefresh {
    if (self.refreshScheduled) return;
    self.refreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBManager *manager = weakSelf;
        if (!manager) return;
        manager.refreshScheduled = NO;
        [manager refresh];
    });
}
// Single source of truth for the unread badge: anchored to the icon's top-right,
// sized from the actual glyph width, never wider than the icon itself.
- (void)layoutBadge:(NFBBubble *)button diameter:(CGFloat)diameter {
    UILabel *badge = button.badge;
    if (!badge) return;
    CGFloat height = MIN(20, MAX(14, diameter * 0.42));
    CGFloat width = height;
    if (badge.text.length) {
        CGSize text = [badge.text sizeWithAttributes:@{NSFontAttributeName: badge.font ?: [UIFont boldSystemFontOfSize:12]}];
        width = MAX(height, MIN(diameter, ceil(text.width) + 10));
    }
    badge.frame = CGRectMake(7 + diameter - width * 0.62, 7 - height * 0.28, width, height);
    badge.layer.cornerRadius = height / 2;
    badge.font = [UIFont boldSystemFontOfSize:MIN(12, height * 0.62)];
    badge.adjustsFontSizeToFitWidth = YES;
    badge.minimumScaleFactor = 0.6;
}
// The column is a window, so `hidden` cannot be animated (it switches the render
// tree off between frames). Translate the root view instead and only flip
// `hidden` once the slide has finished.
- (void)setColumnOffscreen:(BOOL)offscreen {
    UIView *root = self.window ? self.window.rootViewController.view : nil;
    if (!root) { self.window.hidden = offscreen; return; }
    if (offscreen && self.window.hidden) return;
    if (!offscreen && !self.window.hidden && CGAffineTransformIsIdentity(root.transform)) return;
    BOOL animated = !UIAccessibilityIsReduceMotionEnabled();
    CGFloat width = CGRectGetWidth(root.bounds);
    if (!(width > 0)) width = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGAffineTransform away = CGAffineTransformMakeTranslation(width, 0);
    if (!animated) {
        root.transform = CGAffineTransformIdentity;
        self.window.hidden = offscreen;
        self.columnSliding = NO;
        return;
    }
    self.columnSliding = YES;
    self.columnTargetOffscreen = offscreen;
    if (offscreen) {
        [UIView animateWithDuration:0.24 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
            animations:^{ root.transform = away; }
            completion:^(__unused BOOL done) {
                // Only commit the hide if the column is still meant to be away;
                // a keyboard that came back mid-slide must keep it on screen.
                if (self.columnTargetOffscreen) {
                    root.transform = CGAffineTransformIdentity;
                    self.window.hidden = YES;
                    self.columnSliding = NO;
                }
            }];
    } else {
        self.window.hidden = NO;
        // Start from the right edge only when the column was actually parked
        // there; reversing mid-slide continues from the current position instead
        // of snapping back.
        if (CGAffineTransformIsIdentity(root.transform)) root.transform = away;
        [UIView animateWithDuration:0.28 delay:0.04
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
            animations:^{ root.transform = CGAffineTransformIdentity; }
            completion:^(__unused BOOL done) {
                self.window.hidden = NO;
                self.columnSliding = NO;
            }];
    }
}

- (void)refresh {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    [self updatePrivacy];
    NFBUpdateOpenEdge(self.enabled);
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
        if (!atHome) reopened = NFBFrontmostAppID();
    }
    if (reopened.length && ![self.closingApps containsObject:reopened] && [self.dismissedSwitcher containsObject:reopened]) {
        NFBDebugLog(@"refresh: dismissed app %@ reopened -> re-pin", reopened);
        [self.dismissedSwitcher removeObject:reopened];
        if (![self.store.appIDs containsObject:reopened]) [self.store pinApp:reopened];
    }
    NSMutableArray<NSString *> *apps = [NSMutableArray array];
    for (NSString *app in self.store.appIDs) {
        if (NFBIsSystemDesktop(app)) continue;
        BOOL fromSwitcher = [self.lastSwitcher containsObject:app];
        BOOL notificationsAllowed = fromSwitcher || NFBSystemNotificationsAllowed(app, ^{ [NFBManager.shared setNeedsRefresh]; });
        if (fromSwitcher || notificationsAllowed) [apps addObject:app];
    }
    NSString *floatingApp = NFBTrollVisibleApp();
    if ([self.retracting containsObject:floatingApp ?: @""]) floatingApp = nil;
    NFBObserveSplitSwitch(floatingApp, self.closePreviousSplit);
    NFBObserveSplitPlacement(floatingApp);
    // An attachment fallback is layout-only: do not treat it as an app switch.
    floatingApp = NFBSplitAttachmentApp();
    if ([self.retracting containsObject:floatingApp ?: @""]) floatingApp = nil;
    // Keep the fast watcher in step with reality every time we recompute layout.
    // Continue observing orientation even when a lone landscape window has no
    // portrait attachment target and its rail has returned to the screen edge.
    [self syncFloatingWatch:floatingApp ?: NFBTrollVisibleApp()];
    // A keyboard outranks everything else: typing is the one moment the bubbles
    // must be out of the way, so it pulls them all back in no matter what. The
    // ones it pulled in are remembered and popped back out the moment typing
    // ends (split-view bubbles come back on their own via floatingApp below).
    BOOL previousKeyboardUp = self.keyboardUp;
    BOOL keyboardUp = NFBKeyboardVisible();
    self.keyboardUp=keyboardUp;
    BOOL home = NFBCurrentWindowState().home;
    BOOL edgeMode = !floatingApp.length;
    NSString *active = NFBTrollVisibleApp() ?: floatingApp ?: (home ? nil : NFBCurrentWindowState().frontApp);
    if (NFBIsSystemDesktop(active)) active = nil;
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
    NSArray<NSString *> *railApps;
    if (edgeMode) {
        railApps = @[]; // Open owns all edge presentation in this edition.
    } else {
        // Membership, not merely viewport height, is limited to three recent apps.
        NSMutableArray<NSString *> *background = [NSMutableArray array];
        for (NSString *app in apps)
            if ([self.lastSwitcher containsObject:app] || [app isEqual:active]) [background addObject:app];
        railApps = NFBRecentBackgroundThree(background, history.array, self.favoriteApps);
    }
    NSMutableArray<NSString *> *displayApps = [railApps mutableCopy];
    if (!edgeMode) [displayApps addObject:NFBClearAllID];
    BOOL orderChanged = ![self.lastLayoutApps isEqualToArray:displayApps];
    self.lastLayoutApps = [displayApps copy];
    for (NSString *appID in self.buttons.allKeys) {
        if ([displayApps containsObject:appID]) continue;
        NFBBubble *button = self.buttons[appID];
        [self.buttons removeObjectForKey:appID];
        button.userInteractionEnabled = NO;
        if (![self.favoriteApps containsObject:appID]) [self.icons removeObjectForKey:appID];
        if ([self.burstApps containsObject:appID]) {
            [self.burstApps removeObject:appID];
            [self burstBubble:button];
            continue;
        }
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
            button.alpha = 0; button.transform = CGAffineTransformMakeTranslation(self.iconSize + 20, 0);
        } completion:^(__unused BOOL done) {
            // Only tear down if nothing re-adopted this app in the meantime,
            // otherwise a returning notification authors a second bubble.
            if (self.buttons[appID] != button) [button removeFromSuperview];
        }];
    }
    if (!self.enabled) {
        NFBUpdateOpenEdgeSplitIconsVisible(NO);
        NSUInteger presentationEpoch=self.presentationEpoch;
        // Delay hiding until the removal animation completes; recheck new arrivals.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.presentationEpoch==presentationEpoch && !self.enabled) self.window.hidden = YES;
        });
        return;
    }
    if (![self shouldShow]) { NFBUpdateOpenEdgeSplitIconsVisible(NO); self.window.hidden = YES; return; }
    // A keyboard owns the space this column would occupy. Letting it stay on
    // screen left the material strip painted in the top-right corner while the
    // icons themselves collapsed, which reads as a stray shadow, so the column
    // slides out while typing and slides back when the keyboard goes away.
    if (keyboardUp) {
        [self setColumnOffscreen:YES];
        return;
    }
    [self ensureWindow];
    NFBSetCaptureHidden(self.window.rootViewController.view, self.hideInScreenshots);
    [self setColumnOffscreen:NO];
    UIView *root = self.window.rootViewController.view;
    CGFloat oldBottomOffset = MAX(0, self.rail.contentSize.height - self.rail.bounds.size.height) - self.rail.contentOffset.y;
    CGRect bounds = root.bounds;
    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat top = MAX(safe.top, 48) + 30;
    CGRect splitFrame = floatingApp.length ? NFBSplitFrameInView(root) : CGRectNull;
    // During Open's window rebuild the frame is momentarily unavailable while the
    // attachment is still reported. Reuse the last good frame for geometry and for
    // the icon-suppression decision so a rebuild cannot flash the edge icon or
    // collapse the rail; only a genuinely gone attachment clears it.
    if (!floatingApp.length) {
        self.lastSplitFrame = CGRectNull; self.observedSplitFrame = CGRectNull;
    } else if (!CGRectIsNull(splitFrame) && !CGRectIsEmpty(splitFrame) && isfinite(CGRectGetMaxX(splitFrame))) {
        self.lastSplitFrame = splitFrame;
    } else if (!CGRectIsNull(self.lastSplitFrame) && !CGRectIsEmpty(self.lastSplitFrame)) {
        splitFrame = self.lastSplitFrame;
    }
    BOOL attached = floatingApp.length && !CGRectIsNull(splitFrame) && !CGRectIsEmpty(splitFrame);
    // Position gates both our presentation and Open's edge suppression.
    BOOL validSplit = !CGRectIsNull(splitFrame) && !CGRectIsEmpty(splitFrame);
    const CGFloat cornerTolerance = 4.0;
    BOOL atBottomLeft = validSplit &&
        fabs(CGRectGetMinX(splitFrame) - CGRectGetMinX(bounds)) <= cornerTolerance &&
        fabs(CGRectGetMaxY(splitFrame) - CGRectGetMaxY(bounds)) <= cornerTolerance;
    BOOL hideForPosition = floatingApp.length && !atBottomLeft;
    root.userInteractionEnabled = !hideForPosition;
    CGFloat visibility = hideForPosition ? 0 : 1;
    if (root.alpha != visibility) {
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.18 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
            animations:^{ root.alpha = visibility; } completion:nil];
    }
    // Open's edge icon is hidden only while these split bubbles are actually on
    // screen. A fullscreen app, the desktop, landscape/mini-only, or a split
    // parked away from the corner restore native visibility; the adapter separately
    // keeps the fullscreen tray closed and other eligible states expanded.
    NFBUpdateOpenEdgeSplitIconsVisible(floatingApp.length > 0 && !hideForPosition);

    BOOL containerMode = !edgeMode;
    BOOL attachmentChanged = attached != self.splitRailActive;
    self.splitRailActive = attached;
    CGFloat diameter = self.iconSize;
    // Reserve a real gap outside the split window; never change its scale.
    // Only horizontal space constrains icon size, not app count or keyboard height.
    const CGFloat splitGap = 4;
    const CGFloat screenMargin = 4;
    // CGRectNull carries INFINITY in origin (and -INFINITY in size), so any
    // arithmetic on it poisons the result: CGRectGetMaxX(CGRectNull) is -INF and
    // MAX/MIN then clamp the rail to 1pt. `attached` alone is not enough — during
    // Open's window rebuild the frame is briefly null while the attachment is
    // still reported. Only touch the frame when it is genuinely usable.
    BOOL usableSplit = !CGRectIsNull(splitFrame) && !CGRectIsEmpty(splitFrame) && isfinite(CGRectGetMaxX(splitFrame));
    if (attached && usableSplit) {
        CGFloat room = CGRectGetWidth(bounds) - CGRectGetMaxX(splitFrame) - splitGap - screenMargin;
        if (isfinite(room)) diameter = MIN(diameter, MAX(1, room - 14));
    }
    NSTimeInterval layoutDuration = UIAccessibilityIsReduceMotionEnabled() ? 0 : (attachmentChanged ? 0.35 : (attached ? 0.16 : NFBMotion));
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
    // Keyboard placement keeps the row clear while typing. The row
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
    CGFloat railY = anchor + (step - side/2) + padding - height;
    railY = MAX(top, MIN(bounds.size.height - MAX(safe.bottom, 20) - 20 - height, railY));
    CGRect railFrame = CGRectMake(bounds.size.width - railWidth, railY, railWidth, height);
    if (attached && usableSplit) {
        CGFloat y = MAX(safe.top, CGRectGetMinY(splitFrame));
        CGFloat bottom = MIN(CGRectGetHeight(bounds) - safe.bottom, CGRectGetMaxY(splitFrame));
        // A collapsed or inverted span means Open is mid-rebuild; keep the plain
        // rail geometry rather than committing a 1pt strip that then sticks.
        if (isfinite(y) && isfinite(bottom) && bottom - y >= side) height = MAX(1, bottom - y);
        CGFloat x = NFBContainedRailX(CGRectGetMaxX(splitFrame)+splitGap,
            CGRectGetWidth(bounds),railWidth,screenMargin);
        if (isfinite(x)) railFrame = CGRectMake(x, y, railWidth, height);
    }
    CGFloat clearCenterY = railFrame.origin.y - 8 - side / 2;
    CGRect favoritesFrame = CGRectZero;
    UIView *actionTarget = NFBDesktopActionWindow();
    CGRect actionWindowFrame = NFBWindowFrameInView(actionTarget, root);
    CGRect desktopActionFrame = CGRectNull;
    if (containerMode) {
        CGFloat ceiling = MAX(safe.top, 12);
        CGFloat floor = CGRectGetHeight(bounds) - MAX(safe.bottom, 12);
        if (attached && usableSplit) {
            floor = MIN(floor, CGRectGetMaxY(splitFrame) - CGRectGetHeight(splitFrame) * 0.05);
        }
        if (keyboardUp) floor = MIN(floor, NFBKeyboardTopInView(root) - 12 - step);
        CGFloat desiredTop = (attached && usableSplit) ? NFBSplitRailTop(CGRectGetMinY(splitFrame), CGRectGetHeight(splitFrame)) : railFrame.origin.y;
        CGFloat y = MAX(ceiling, MIN(desiredTop, floor - side - 9));
        // The action occupies its own row above both rails, never inside scrolling content.
        if (actionTarget && !CGRectIsNull(actionWindowFrame) && floor - y >= 2 * side + 18) {
            desktopActionFrame = CGRectMake(railFrame.origin.x, y, side, side);
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
    // A changing clipped viewport must not race independently animated child
    // sizes and scroll bounds. Commit resize geometry together, then keep the
    // normal animation timing for subsequent moves within a stable viewport.
    // A changing clipped viewport must not race independently animated children,
    // but zeroing the duration for the whole pass turned every bubble into an
    // instant jump on each split/fullscreen toggle. Commit the new size first and
    // let the children keep a normal, short duration.
    BOOL viewportResized = !CGSizeEqualToSize(self.rail.bounds.size, railFrame.size) ||
        !CGSizeEqualToSize(self.favoritesRail.bounds.size, favoritesFrame.size);
    CGFloat childDuration = viewportResized ? 0 : layoutDuration;
    [self layoutFavorites:favoritesFrame diameter:diameter active:active duration:childDuration];
    [self layoutDesktopAction:desktopActionFrame target:actionTarget duration:childDuration];
    BOOL hideEdgeIcons = edgeMode;
    self.rail.hidden = hideEdgeIcons;
    self.railMaterial.hidden = hideEdgeIcons;
    BOOL railSizeChanged = !CGSizeEqualToSize(self.rail.bounds.size, railFrame.size);
    // Narrow only the visible edge material. Retain the padded hit/clip area
    // so icon edges, shadows and the external unread badges stay intact.
    CGRect materialFrame = edgeMode ? CGRectInset(railFrame, 5, 0) : railFrame;
    self.rail.alwaysBounceVertical = contentHeight > height;
    self.rail.showsVerticalScrollIndicator = NO;
    if (!CGRectEqualToRect(self.rail.frame, railFrame) || self.railMaterial.alpha != (rowCount && height > 0 ? 0.55 : 0)) {
        if (CGRectIsEmpty(self.rail.frame)) self.rail.frame = railFrame;
        [UIView animateWithDuration:layoutDuration delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
            animations:^{
                self.rail.frame = railFrame;
                self.rail.layer.cornerRadius = MIN(14, railWidth / 4);
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
        BOOL revealActive=activeIndex != NSNotFound && (attachmentChanged || orderChanged ||
                ![self.lastRailActive isEqual:active] || keyboardUp != previousKeyboardUp || railSizeChanged);
        if (revealActive)
            offset = NFBRevealOffset(offset, height, contentHeight, NFBRowCenter(rowCount, activeIndex, step, side), side);
        self.lastRailActive = active;
        if (revealActive) {
            NFBSettleRailOffset(self.rail,offset);
        } else if (!CGPointEqualToPoint(self.rail.contentOffset, CGPointMake(0, offset))) [UIView animateWithDuration:layoutDuration delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
            animations:^{ self.rail.contentOffset = CGPointMake(0, offset); } completion:nil];
    }
    [displayApps enumerateObjectsUsingBlock:^(NSString *appID, __unused NSUInteger index, __unused BOOL *stop) {
        BOOL isClearAll = [appID isEqualToString:NFBClearAllID];
        NSUInteger rowIndex = [railApps indexOfObject:appID];
        UIView *parent = isClearAll ? root : self.rail;
        NFBBubble *button = self.buttons[appID];
        BOOL fresh = !button;
        if (fresh) {
            button = [[NFBBubble alloc] initWithFrame:CGRectZero];
            button.appID = appID;
            if (isClearAll) {
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
                __weak NFBBubble *weakBubble = button;
                __weak typeof(self) weakManager = self;
                button.tapHandler = ^{
                    NFBBubble *strongBubble = weakBubble;
                    if (strongBubble) [weakManager tapped:strongBubble];
                };
                UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appHeld:)];
                hold.minimumPressDuration = 0.45;
                hold.cancelsTouchesInView = YES;
                hold.delegate = self;
                [singleTap requireGestureRecognizerToFail:hold];
                [button addGestureRecognizer:singleTap];
                [button addGestureRecognizer:hold];
            }
            self.buttons[appID] = button;
            [parent addSubview:button];
        }
        button.hidden = hideEdgeIcons;
        if (button.superview != parent) {
            // Preserve screen position when moving between unread strip and rail.
            CGPoint position = [button.superview convertPoint:button.center toView:parent];
            [parent addSubview:button];
            button.center = position;
        }
        if (isClearAll) {
            [self styleClearAllButton:button];

        }
        else [self updateBubble:button record:[self.store latestForApp:appID]];
        if (!isClearAll) [self layoutBadge:button diameter:diameter];
        // A bubble we already started retracting must not be re-expanded by the
        // stale "window still visible" reading taken mid-transition.
        // edgeMode hides the rail and every bubble; animating them is pure cost and
        // leaves the model values jumping when they come back.
        [button updateActiveMark:(!isClearAll && [active isEqualToString:appID])
            diameter:diameter duration:(hideEdgeIcons ? 0 : layoutDuration)];
        CGAffineTransform target = CGAffineTransformIdentity;
        CGRect targetBounds = CGRectMake(0, 0, side, side);
        // Keep the same bottom-first app ordering on desktop and in split view.
        // The clear action is appended last and therefore stays above all apps.
        CGFloat rowY = isClearAll ? side / 2 : NFBRowCenter(rowCount, rowIndex, step, side);
        CGFloat corner = !isClearAll ? diameter * 0.23 : diameter / 2;
        CGPoint targetCenter = isClearAll ? CGPointMake(CGRectGetMidX(railFrame), clearCenterY) : CGPointMake(side / 2, rowY);
        if (fresh) {
            button.bounds = targetBounds;
            button.center = targetCenter;
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = corner;
            button.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(7, 7, diameter, diameter)].CGPath;
            button.transform = CGAffineTransformMakeTranslation(side + 10, 0);
            button.alpha = 0;
        }
        // The clear-all bubble is an action, not an app: keep it fully opaque so
        // it stays discoverable, unlike the dimmed background bubbles around it.
        CGFloat alpha = self.iconOpacity;
        if (isClearAll) {
            alpha = 1.0;
        } else if ([active isEqualToString:appID]) {
            alpha = 1.0;
        }
        BOOL changed = fresh || fabs(button.imageView.layer.cornerRadius - corner) > 0.01 || !CGRectEqualToRect(button.bounds, targetBounds) ||
            !CGPointEqualToPoint(button.center, targetCenter) ||
            !CGAffineTransformEqualToTransform(button.transform, target) ||
            fabs(button.alpha - alpha) > 0.001;
        void (^apply)(void) = ^{
            // Bounds/center remain valid even while the view is transformed.
            button.bounds = targetBounds;
            button.center = targetCenter;
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = corner;
            button.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(7, 7, diameter, diameter)].CGPath;
            button.transform = target;
            button.alpha = alpha;
        };
        if (changed && hideEdgeIcons) {
            // Nothing is visible; commit the model values without submitting an
            // animation that the compositor still has to commit.
            apply();
        } else if (changed && isClearAll) {
            // The clear-all bubble lives on the root view while its position is
            // derived from the rail's target frame. Matching the rail's curve and
            // duration keeps the two from visibly separating mid-transition.
            [UIView animateWithDuration:layoutDuration delay:0
                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
                animations:apply completion:nil];
        } else if (changed) {
            [UIView animateWithDuration:layoutDuration
                delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0
                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                animations:apply completion:nil];
        }
    }];
}
- (void)layoutFavorites:(CGRect)frame diameter:(CGFloat)diameter active:(NSString *)active duration:(NSTimeInterval)duration {
    UIView *root = self.window.rootViewController.view;
    if (!self.favoritesRail) {
        self.favoriteButtons = [NSMutableDictionary dictionary];
        self.favoritesRail = [NFBRail new];
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
    if ((visible && !CGRectEqualToRect(self.favoritesRail.frame, frame)) || self.favoritesRail.alpha != (visible ? 1 : 0) || self.favoritesMaterial.alpha != (visible ? 0.55 : 0) || self.favoritesRail.layer.cornerRadius != MIN(14, side / 4)) [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (visible) { self.favoritesRail.frame = frame; self.favoritesMaterial.frame = frame; }
        self.favoritesRail.alpha = visible ? 1 : 0;
        self.favoritesMaterial.alpha = visible ? 0.55 : 0;
        self.favoritesRail.layer.cornerRadius = MIN(14, side / 4);
        self.favoritesMaterial.layer.cornerRadius = MIN(14, side / 4);
    } completion:nil];
    for (NSString *app in self.favoriteButtons.allKeys) if (![self.favoriteApps containsObject:app]) {
        [self.favoriteButtons[app] removeFromSuperview]; [self.favoriteButtons removeObjectForKey:app];
    }
    if (!visible) return;
    CGFloat content = self.favoriteApps.count ? (self.favoriteApps.count - 1) * step + side : 0;
    CGFloat maxOffset = MAX(0, content - frame.size.height);
    self.favoritesRail.contentSize = CGSizeMake(side, content);
    self.favoritesRail.alwaysBounceVertical = content > frame.size.height;
    if (!self.favoriteDrag && !self.favoritesRail.dragging && !self.favoritesRail.decelerating && visible) {
        CGFloat offset = MAX(0, MIN(maxOffset, maxOffset - (wasHidden ? MAX(0, self.favoriteScrollRows) * step : oldBottomDistance)));
        NSUInteger activeIndex = [self.favoriteApps indexOfObject:active ?: @""];
        BOOL revealActive=activeIndex != NSNotFound && (wasHidden || resized || ![self.lastFavoritesActive isEqual:active]);
        if (revealActive)
            offset = NFBRevealOffset(offset, frame.size.height, content,
                NFBRowCenter(self.favoriteApps.count, activeIndex, step, side), side);
        self.lastFavoritesActive = active;
        if (revealActive) {
            NFBSettleRailOffset(self.favoritesRail,offset);
        } else if (!CGPointEqualToPoint(self.favoritesRail.contentOffset, CGPointMake(0, offset))) [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.favoritesRail.contentOffset = CGPointMake(0, offset);
        } completion:nil];
    }
    [self.favoriteApps enumerateObjectsUsingBlock:^(NSString *app, NSUInteger index, __unused BOOL *stop) {
        NFBBubble *button = self.favoriteButtons[app];
        if (!button) {
            button = [[NFBBubble alloc] initWithFrame:CGRectMake(0, 0, side, side)]; button.appID = app;
            UITapGestureRecognizer *favoriteTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(favoriteTapped:)];
            // VoiceOver activation path (batch 4) and the gesture path (batch 2)
            // share the same guard, so both are kept here.
            __weak NFBBubble *weakFavorite = button;
            __weak typeof(self) weakOwner = self;
            button.tapHandler = ^{
                NFBBubble *strongBubble = weakFavorite;
                if (!strongBubble) return;
                if (weakOwner.favoriteDragConsumed) { weakOwner.favoriteDragConsumed = NO; return; }
                if (weakOwner.favoriteDrag) return;
                [weakOwner tapped:strongBubble];
            };
            if (self.favoriteHold) [favoriteTap requireGestureRecognizerToFail:self.favoriteHold];
            [button addGestureRecognizer:favoriteTap];
            self.favoriteButtons[app] = button; [self.favoritesRail addSubview:button];
        }
        [self updateBubble:button record:[self.store latestForApp:app]];
        [button updateActiveMark:[app isEqual:active] diameter:diameter duration:duration];
        [self layoutBadge:button diameter:diameter];
        CGPoint targetCenter = CGPointMake(side / 2, NFBRowCenter(self.favoriteApps.count, index, step, side));
        BOOL changed = !CGRectEqualToRect(button.bounds, CGRectMake(0,0,side,side)) || (button != self.favoriteDrag && !CGPointEqualToPoint(button.center, targetCenter)) || !CGRectEqualToRect(button.imageView.frame, CGRectMake(7,7,diameter,diameter)) || button.imageView.layer.cornerRadius != diameter * 0.23 || button.alpha != ([app isEqual:active] ? 1 : self.iconOpacity);
        if (changed) [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            button.bounds = CGRectMake(0, 0, side, side);
            if (button != self.favoriteDrag) button.center = CGPointMake(side / 2, NFBRowCenter(self.favoriteApps.count, index, step, side));
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = diameter * 0.23;
            button.alpha = [app isEqual:active] ? 1 : self.iconOpacity;
        } completion:nil];
    }];
}
// One synchronise per burst of preference writes, off the drag-release frame.
- (void)schedulePreferenceFlush {
    if (self.preferenceFlushPending) return;
    self.preferenceFlushPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NFBManager *manager = weakSelf;
        if (!manager) return;
        manager.preferenceFlushPending = NO;
        CFPreferencesAppSynchronize(NFBDomain);
    });
}
- (void)saveFavoritePosition {
    if (!self.favoritesRail || self.favoritesRail.alpha < 0.01) return;
    CGFloat step = MAX(1, self.favoritesRail.contentSize.width - 5);
    CGFloat distance = MAX(0, self.favoritesRail.contentSize.height - self.favoritesRail.bounds.size.height - self.favoritesRail.contentOffset.y);
    self.favoriteScrollRows = distance / step;
    CFPreferencesSetAppValue(CFSTR("FavoriteScrollRows"), (__bridge CFPropertyListRef)@(self.favoriteScrollRows), NFBDomain);
}
- (void)finishFavoriteDrag {
    [self.favoriteDragTimer invalidate]; self.favoriteDragTimer = nil;
    if (!self.favoriteDrag) return;
    // Fold the two preference writes below into one flush instead of two
    // synchronous, cross-process synchronises on the frame the drag is released.
    [self schedulePreferenceFlush];
    if (self.favoriteDragConsumed) {
        // Any tap from this gesture is delivered before the next runloop turn.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.favoriteDragConsumed = NO;
        });
    }
    self.favoriteDrag.layer.zPosition = 0;
    self.favoriteDrag = nil;
    self.favoritesRail.scrollEnabled = YES;
    CFPreferencesSetAppValue(CFSTR("FavoriteOrder"), (__bridge CFPropertyListRef)self.favoriteApps, NFBDomain);
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
        if (self.favoriteDrag) self.favoriteDragConsumed = YES;
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
    // contentSize.width is 0 while the rail is freshly created or hidden; step
    // then became 1 and the row computation produced a huge index that re-ran a
    // reorder animation on every tick.
    if (rail.contentSize.width < 8 || rail.contentSize.height < 8) return;
    CGPoint point = [self.favoriteHold locationInView:rail];
    CGFloat localY = point.y - rail.contentOffset.y;
    // Edge zones were 28pt against a 62pt bubble: reaching them needed a long
    // hover. Use 44pt (the HIG minimum) and scale the step with how deep the
    // finger is inside the zone so the list scrolls faster the further you pull.
    const CGFloat edge = 44;
    CGFloat delta = 0;
    if (localY < edge) delta = -ceil((edge - MAX(0, localY)) / 6.0) - 1;
    else if (localY > rail.bounds.size.height - edge)
        delta = ceil((MIN(rail.bounds.size.height, localY) - (rail.bounds.size.height - edge)) / 6.0) + 1;
    delta = MAX(-14, MIN(14, delta));
    CGFloat maxOffset = MAX(0, rail.contentSize.height - rail.bounds.size.height);
    rail.contentOffset = CGPointMake(0, MAX(0, MIN(maxOffset, rail.contentOffset.y + delta)));
    point = [self.favoriteHold locationInView:rail];
    CGFloat side = rail.contentSize.width;
    CGFloat step = MAX(1, side - 5);  // layoutFavorites: side = diameter + 14, step = diameter + 9
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
// Cooldown is per target, not global: only a repeat on the SAME target is
// suppressed. Keyed by appID / action identifier.
- (BOOL)acceptGesture {
    return [self acceptGestureForKey:@"global"];
}
- (BOOL)acceptGestureForKey:(NSString *)key {
    NSTimeInterval now = CACurrentMediaTime();
    NSNumber *previous = self.gestureTimes[key];
    if (previous && now - previous.doubleValue < NFBGestureCooldown) return NO;
    if (self.gestureTimes.count >= 64) [self.gestureTimes removeAllObjects];
    self.gestureTimes[key] = @(now);
    return YES;
}
// A bubble belongs to the app currently occupying the TrollOpen floating window.
// Resolved through one place so tap and long press can never disagree.

// Grow the floating window back to fullscreen (single tap). Refreshes slightly
// later, because TrollOpen re-parents the scene across a run loop turn.
- (void)fullscreenFloatingApp:(NSString *)app {
    NFBDebugLog(@"gesture: tap on floating app %@ -> fullscreen", app);
    // Retract first, then hand off: both animations now start on the same frame
    // instead of the bubble waiting for TrollOpen to finish the transition.
    [self beginRetracting:app];
    if (!NFBFullscreenCurrentFloatingWindow())
        [self showOpenNotice:@"TrollOpen 全屏接口不可用，请确认已安装适配的 1.3.7 隐根版并重启桌面"];
}
- (void)closeBubble:(NFBBubble *)button {
    if (self.buttons[button.appID] != button) return;
    if (![self acceptGestureForKey:button.appID ?: @"close"]) return;
    NSString *app = button.appID;
    NSUInteger exitVersion = [self.generations[app] unsignedIntegerValue];
    NSUInteger exitEpoch = self.exitEpoch;
    NSInteger processID = NFBRunningProcessID(app);
    NFBWindowState *initial = NFBCurrentWindowState();
    BOOL wasActive = [app isEqual:initial.frontApp] || [app isEqual:initial.floatingApp];
    // Suppress touch-up activation while the queued burst removes this control.
    button.opening = YES;
    button.userInteractionEnabled = NO;
    [self.dismissedSwitcher addObject:app];
    [self.closingApps addObject:app];
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
        NFBDebugLog(@"gesture: long press on app %@ -> terminate", app);
        NFBInvalidateWindowState();
        NFBWindowState *state = NFBCurrentWindowState();
        BOOL becameActive = (!wasActive && ([app isEqual:state.frontApp] || [app isEqual:state.floatingApp])) || (processID > 1 && processID != NFBRunningProcessID(app));
        if (NFBExitStillCurrent(exitVersion, [self.generations[app] unsignedIntegerValue], self.enabled && self.exitEpoch == exitEpoch, becameActive, NO)) NFBTerminateApp(app);
        [self refresh];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Always clear: a notification arriving inside this window bumps the
            // generation, and the old guard then left the app in closingApps with
            // no bubble able to come back for it.
            [self.closingApps removeObject:app];
        });
    });
}
- (void)burstBubble:(NFBBubble *)button {
    UIView *root = self.window.rootViewController.view;
    CGFloat measured = button.imageView.bounds.size.width;
    // During a size animation the diameter can read 0, which collapsed the ring
    // and all twelve particles onto one invisible point.
    if (UIAccessibilityIsReduceMotionEnabled() || measured < 8 || root.hidden || root.alpha < 0.01) {
        [UIView animateWithDuration:0.15 animations:^{ button.alpha = 0; }
            completion:^(__unused BOOL done) { [button removeFromSuperview]; }];
        return;
    }
    // Capture presentation geometry so a long press during sliding does not jump.
    CALayer *presentation = (CALayer *)button.layer.presentationLayer;
    CALayer *sourceLayer = presentation ?: button.layer;
    CGPoint origin = [sourceLayer convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toLayer:root.layer];
    CGFloat diameter = measured;
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
        // Absolute scale, not CGAffineTransformScale on the current model value:
        // a repeated burst multiplied 1.16^n and inherited any exit translation.
        button.transform = CGAffineTransformMakeScale(1.16, 1.16); button.alpha = 0;
    } completion:^(__unused BOOL done) { [button removeFromSuperview]; }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture == self.desktopActionTap || gesture == self.desktopActionHold) {
        self.desktopActionTouchTarget = self.desktopActionTarget;
        return self.enabled && ![self isLocked] && self.desktopActionTouchTarget != nil;
    }
    return YES;
}
- (void)appHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state==UIGestureRecognizerStateBegan) [self closeBubble:(NFBBubble *)gesture.view];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == self.favoritesRail && !decelerate) [self saveFavoritePosition];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.favoritesRail) [self saveFavoritePosition];
}
- (void)singleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    [self tapped:button];
}
// Favorites also live on the rail that hosts the long-press drag. Behind
// requireGestureRecognizerToFail: this flag is the second line of defence
// against a reorder releasing into a tap.
- (void)favoriteTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    if (self.favoriteDragConsumed) { self.favoriteDragConsumed = NO; return; }
    NFBBubble *button = (NFBBubble *)gesture.view;
    if (self.favoriteDrag || !button) return;
    [self tapped:button];
}
- (void)tapped:(NFBBubble *)button {
    if (button.opening || (self.buttons[button.appID] != button && self.favoriteButtons[button.appID] != button)) return;
    if (self.pendingRecord && [self.pendingRecord.appID isEqual:button.appID]) return;
    if (![self acceptGestureForKey:button.appID ?: @"tap"]) return;
    NFBCloseDesktopSplit();
    self.generations[button.appID] = @([self.generations[button.appID] unsignedIntegerValue] + 1);
    [self.closingApps removeObject:button.appID];
    button.opening = YES;
    [self refresh];
    NFBRecord *record = [self.store latestForApp:button.appID];
    // Dispatch in this same event, never in the animation completion.
    if (record) {
        BOOL locked = [self isLocked];
        if ([self executeRecord:record authentication:locked]) {
            // Park until tick sees the app frontmost. Consuming here meant a
            // cancelled authentication (or a slow hand-off) silently dropped the
            // notification: the bubble vanished and nothing opened.
            self.pendingRecord = record;
            self.pendingUntil = CACurrentMediaTime() + (locked ? 8 : 3);
        }
    } else [self openApp:button.appID];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ button.opening = NO; });
}
- (void)showOpenNotice:(NSString *)message {
    if (!message.length) return;
    // A non-modal message keeps the overlay from taking keyboard or app focus.
    [self ensureWindow];
    UIView *root = self.window.rootViewController.view;
    if (!self.noticeLabel) {
        UILabel *label = [UILabel new];
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:14];
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.85];
        label.layer.cornerRadius = 12; label.clipsToBounds = YES;
        label.userInteractionEnabled = NO;
        self.noticeLabel = label;
    }
    UILabel *notice = self.noticeLabel;
    // One reused view: repeated notices used to stack a new label per call.
    [notice.layer removeAllAnimations];
    [notice removeFromSuperview];
    notice.alpha = 1;
    notice.text = message;
    CGFloat width = MIN(320, root.bounds.size.width - 32);
    CGSize fitted = [message boundingRectWithSize:CGSizeMake(width - 24, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:@{NSFontAttributeName: notice.font} context:nil].size;
    CGFloat height = MAX(44, ceil(fitted.height) + 24);
    notice.frame = CGRectMake((root.bounds.size.width - width) / 2,
        MAX(root.safeAreaInsets.top, 44) + 12, width, height);
    [root addSubview:notice];
    [root bringSubviewToFront:notice];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    self.noticeToken++;
    NSUInteger token = self.noticeToken;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NFBManager *manager = weakSelf;
        if (!manager || manager.noticeToken != token) return;
        UILabel *current = manager.noticeLabel;
        if (!current.superview) return;
        [UIView animateWithDuration:0.2 animations:^{ current.alpha = 0; }
            completion:^(__unused BOOL done) { [current removeFromSuperview]; }];
    });
}
- (void)openApp:(NSString *)app {
    NFBResetSplitPlacement();
    if ([self isLocked]) {
        [self showOpenNotice:@"请先解锁，再点击图标通过 TrollOpen 分屏打开"];
        return;
    }
    // Cross-process read plus a synchronous flush on every tap. A short cache is
    // enough: the user cannot toggle TrollOpen's switch faster than this.
    static BOOL cachedEnabled;
    static BOOL cachedValid;
    static CFTimeInterval cachedAt;
    if (!cachedValid || CACurrentMediaTime() - cachedAt > 2.0) {
        CFStringRef domain = CFSTR("com.charlieleung.trollopenjbprefs");
        CFPreferencesAppSynchronize(domain);
        id read = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("enabled"), domain));
        cachedEnabled = [read respondsToSelector:@selector(boolValue)] && [read boolValue];
        cachedValid = YES; cachedAt = CACurrentMediaTime();
    }
    id enabled = cachedEnabled ? @YES : nil;
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
    NSString *front = NFBFrontmostAppID();
    BOOL home = NFBCurrentWindowState().home;
    BOOL submitted;
    if (!home && [front isEqualToString:app]) {
        // Do not fall back to the generic path: that path left a black backdrop
        // when the very same app was still occupying the fullscreen scene.
        submitted = NFBSplitTrollFrontmostApp();
    } else {
        submitted = NFBOpenTrollApp(app);
    }
    if (!submitted)
        [self showOpenNotice:@"TrollOpen 分屏接口不可用，请确认已安装适配的 1.3.7 隐根版并重启桌面"];
}
- (BOOL)executeRecord:(NFBRecord *)record {
    return [self executeRecord:record authentication:YES];
}
- (BOOL)executeRecord:(NFBRecord *)record authentication:(BOOL)authentication {
    id action = NFBGet(record.request, @"defaultAction");
    id delegate = NFBGet(record.destination, @"delegate");
    SEL selector = @selector(destination:executeAction:forNotificationRequest:requestAuthentication:withParameters:completion:);
    NSMethodSignature *signature = NFBSignature(delegate, selector);
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
            requestAuthentication:authentication withParameters:@{} completion:^{}];
        return YES;
    } @catch (__unused NSException *error) {
        NSLog(@"[NotifyBubbles] Notification action failed; bubbles retained.");
        return NO;
    }
}
@end
