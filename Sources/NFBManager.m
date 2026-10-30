#import "NFBRailScrolling.h"
#import "NFBDesktopHost.h"
#import "NFBHotspot.h"
#import "NFBSystemDesktop.h"
#import "NFBOpenConsole.h"
#import "NFBWindowState.h"
#import "NFBTransitionPolicy.h"
#import "NFBMotionPolicy.h"
#import "NFBColumnMotionPolicy.h"
#import "NFBHitPolicy.h"
#import "NFBActionGesturePolicy.h"
#import "NFBIcon.h"
#import "NFBManager.h"
#import "NFBPrivate.h"
#import "NFBStore.h"
#import "NFBGeometry.h"
#import "NFBRailLayout.h"
#import "NFBRailStateStore.h"
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
#import "NFBRailMetricQueue.h"
#import "NFBProbePolicy.h"
#import "NFBFavoriteDragPolicy.h"
#import "NFBBurstPolicy.h"
#import "NFBDesktopActionPolicy.h"
#import "NFBTickReconcile.h"

static const NSTimeInterval NFBMotion = 0.35;
// No double-tap recognizer: a short tap resolves on release.
// Guard against repeated callbacks from the same completed gesture.
static const NSTimeInterval NFBGestureCooldown = 0.25;
// Coalesced persistence of the split column geometry. A split lays out at display
// rate, so the record is committed at most this often and only when it changed.
static const NSTimeInterval NFBRailStateWriteDelay = 1.0;

// Vertical position (0 = top, 1 = bottom) the whole row shifts to while an app
// is in the split view, so it clears the floating window. Restores on exit.
static const CGFloat NFBFloatingPosition = 0.80;
// Keyboard placement is not a constant here: the column is hidden entirely while
// typing (see setColumnOffscreen:), so there is no keyboard position to blend.
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

// The rail asks its owner for a row hanging past its bounds. A protocol, not a
// direct NFBManager reference: NFBRail is defined before the manager's class
// extension, and only a *previously declared* interface is visible there.
@class NFBRail;
@protocol NFBRailHitDelegate <NSObject>
- (UIView *)rail:(NFBRail *)rail bubbleAtPoint:(CGPoint)point withEvent:(UIEvent *)event;
@end

// Both active rails are ordinary interactive scroll containers.
@interface NFBRail : UIScrollView
@property(nonatomic, weak) id<NFBRailHitDelegate> nfbHitDelegate;
@end
@implementation NFBRail
// A half-hidden row hangs past this scroll view's right edge, and UIKit refuses a
// touch outside a view's bounds before any gesture sees it. Only rows that really
// have an on-screen part outside the rail are offered here; everything inside is
// untouched, and the manager refuses the part that is off screen.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit && hit != self) return hit;
    return [self.nfbHitDelegate rail:self bubbleAtPoint:point withEvent:event] ?: hit;
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
@property(nonatomic, copy) void (^tapHandler)(void);
@property(nonatomic, strong) UILabel *badge;
@property(nonatomic, strong) UIView *activeMark;
// Bumped only when the badge content changes, so a refresh that repeats the same
// count never restarts the badge animation (and an interrupted removal can tell
// whether it still owns the view).
@property(nonatomic) unsigned long long badgeContentVersion;
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
    // Half-hidden rows are clipped at the screen edge: the mark may only be drawn
    // while the icon it belongs to is visible.
    self.activeMark.hidden = !active;
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

@interface NFBManager () <UIScrollViewDelegate, UIGestureRecognizerDelegate, NFBRailHitDelegate>
@property(nonatomic, strong) NFBStore *store;
@property(nonatomic, strong) NFBWindow *window;
@property(nonatomic, strong) NFBRail *rail;

@property(nonatomic, strong) NFBBubble *desktopActionButton;
@property(nonatomic, strong) UITapGestureRecognizer *desktopActionTap;
@property(nonatomic, strong) UILongPressGestureRecognizer *desktopActionHold;
@property(nonatomic, strong) UISwipeGestureRecognizer *desktopActionSwipe;
@property(nonatomic, weak) UIView *desktopActionTarget;
@property(nonatomic, weak) UIView *desktopActionTouchTarget;
@property(nonatomic, weak) UIView *observedActionTarget;
@property(nonatomic) CGRect observedActionFrame;
- (void)desktopActionTapped:(UITapGestureRecognizer *)gesture;
- (void)desktopActionHeld:(UILongPressGestureRecognizer *)gesture;
- (void)desktopActionSwiped:(UISwipeGestureRecognizer *)gesture;
- (NFBActionMode)desktopActionMode;
- (void)performDesktopAction:(NFBActionEffect)effect;
- (void)clearUnreadKeepingExpanded;
- (void)layoutDesktopAction:(CGRect)frame target:(UIView *)target split:(BOOL)splitNow toggleFrame:(CGRect)toggleFrame duration:(NSTimeInterval)duration;

@property(nonatomic, strong) NFBRail *favoritesRail;
@property(nonatomic, strong) UIVisualEffectView *favoritesMaterial;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *favoriteButtons;
@property(nonatomic, copy) NSArray<NSString *> *favoriteApps;
@property(nonatomic, strong) UILongPressGestureRecognizer *favoriteHold;
@property(nonatomic, strong) NFBBubble *favoriteDrag;
@property(nonatomic, strong) NSTimer *favoriteDragTimer;
@property(nonatomic) CGFloat favoriteGrabOffset;
// Favorite drag: the idle edge-scroll clock and the finger position it last saw.
// The 30 Hz timer never moves the row on its own; it only repeats the move while
// the finger rests in a 44pt edge zone (NFBFavoriteDragPolicy.h).
@property(nonatomic) CGPoint favoriteDragFingerPoint;
- (void)moveFavoriteDriven:(BOOL)fingerDriven;
- (void)updateFavoriteDragClock;
- (BOOL)favoriteIdleZoneActive;
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
@property(nonatomic) BOOL edgeExpanded;
@property(nonatomic) NSUInteger notifiedCount;
// One layout after a clear unread: keep the expanded column's app rows.
@property(nonatomic) BOOL holdsClearedColumn;
@property(nonatomic) BOOL desktopActionToggle;
@property(nonatomic) BOOL desktopActionParked;
// Collapsed fullscreen column: the control shares the rows' shift and alpha.
@property(nonatomic) BOOL desktopActionHalfHidden;
@property(nonatomic) CFTimeInterval lastInteractionAt;
- (void)closeBubble:(NFBBubble *)button;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBBubble *> *buttons;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *icons;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *imageRetryAfter;
@property(nonatomic, strong) NSMutableSet<NSString *> *burstApps;
// Apps that received a notification in this burst and still owe a shake/scroll.
@property(nonatomic, strong) NSMutableSet<NSString *> *pendingBurstApps;
// One burst layout per turn: a request arriving while one is scheduled joins it.
@property(nonatomic) BOOL burstRefreshPending;
- (void)runBurstEffects;
- (void)refreshIfNeeded;
// The layout pass is running: further requests join it instead of nesting.
@property(nonatomic) BOOL layoutRecording;
// Same-round probe reuse on the 20 Hz watcher path (NFBProbePolicy.h).
// The probe stamps are ivars declared in the @implementation below (a class
// extension may hold declarations only, not variables), for the same-reason
// comment there.
@property(nonatomic) double desktopProbeLateRetry;
@property(nonatomic) BOOL floatingWatchClassMissing;
// Rounds are the unique object touched by every 20 Hz entry point (watcher,
// tick, notification request) this turn; a later dispatch block reads the same
// object and therefore the same round. NSObject identity, not a counter: nothing
// has to be reset between turns.
@property(nonatomic) NSObject *probeRoundToken;
// Bounded reconciliation (NFBTickReconcile.h). The tick's state comparison only
// sees the unread records this plugin stores, so a badge that changed outside
// SpringBoard's notification path - or any other system-side withdraw - produces
// no record change here and the comparison would answer "nothing changed"
// forever. To keep the original behaviour, where the tick submitted a full
// layout every 0.5s and nothing inside the layout could be stale, the tick now
// forces one full layout at least every kTickReconcileInterval seconds (see
// -tickBody). This is a real backstop, not a claim that the field comparison
// covers it: only the tick is unbounded, while the burst layout, gestures, the
// probes and the 20 Hz watcher stay deduped exactly as the perf change made them.
@property(nonatomic) CFTimeInterval lastLayoutAt;
// Written by -refresh: did this pass actually lay the column out (not disabled /
// locked / keyboard)? A pass that did not must not refresh lastLayoutAt above.
@property(nonatomic) BOOL lastRefreshComplete;
// Tick (2 Hz) dirty state: what a full layout would read, compared in the tick
// itself so an unchanged state does not submit a 20 Hz layout. NFBTickReconcile.h
// holds the comparison; `tickStateValid` is NO until the first tick has stored a
// baseline, so the first comparison always lays out. The baseline is a C struct
// and therefore an ivar: a synthsized property would hand out a temporary.
@property(nonatomic) BOOL tickForcedRefresh;
@property(nonatomic) BOOL tickStateValid;
// The tick baseline itself is an ivar in the @implementation below.
@property(nonatomic) BOOL lastLocked;
@property(nonatomic, copy) NSString *tickActiveFloating;
- (UIView *)desktopTargetProbe:(BOOL *)probed;
- (CGRect)splitFrameProbe:(BOOL *)probed;
@property(nonatomic, strong) NSArray<NSString *> *lastSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *dismissedSwitcher;
@property(nonatomic, strong) NSMutableSet<NSString *> *closingApps;
@property(nonatomic) NSUInteger exitEpoch;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *retractTokens;
@property(nonatomic) NSUInteger presentationEpoch;
@property(nonatomic) BOOL closePreviousSplit, hideInScreenshots;
@property(nonatomic) BOOL refreshScheduled;
@property(nonatomic) BOOL columnSliding;
// Bumped on every column slide so a stale completion cannot hide a newer state.
@property(nonatomic) NSUInteger columnSlideToken;
@property(nonatomic) BOOL columnTargetOffscreen;
// The column is parked off the right edge / its transform is meaningful. Reduce
// motion and a missing root flip `hidden` without touching the transform.
@property(nonatomic) BOOL columnParked, columnParkedEver, columnTouchesKnown;
@property(nonatomic) BOOL preferenceFlushPending;
@property(nonatomic, strong) UILabel *noticeLabel;
@property(nonatomic) NSUInteger noticeToken;
@property(nonatomic) CGFloat favoriteScrollRows;
@property(nonatomic) BOOL favoriteDragConsumed;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *generations;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastBadges;
// Unread count each button showed last, so the badge only animates on change.
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *badgeCounts;
// Badge content version last animated per app, so an unchanged count never
// restarts the pop animation on the next 20 Hz pass.
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastBadgeVersion;
@property(nonatomic, strong) NFBRecord *pendingRecord;
@property(nonatomic) NSTimeInterval pendingUntil;
@property(nonatomic) NSUInteger emptyReads;
@property(nonatomic) CGFloat verticalPosition;
@property(nonatomic, copy) NSString *lastActiveApp;
// The fullscreen app the collapsed column keeps as its own row even without a
// notification; nil unless the column is collapsed, not split and an app really is
// frontmost. That state dims the whole column and shows the left half of it.
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
// Last genuine split column geometry. The fullscreen column reuses both so its
// icons keep the split size and top edge even after the split is gone.
@property(nonatomic) CGFloat splitRailDiameter;
@property(nonatomic) CGFloat splitRailTop;
@property(nonatomic) CGFloat splitRailScreenWidth;
@property(nonatomic) BOOL splitRailMeasured;
// Last split geometry restored from disk (nil/false when none was usable). The
// restore happens once, on creation; later writes are debounced by the store.
@property(nonatomic, strong) NFBRailStateStore *railStateStore;
@property(nonatomic) NFBRailMetric restoredRailMetric;
@property(nonatomic) BOOL restoredRailMetricValid;
// Width the restored record was last checked against; 0 until the first layout.
@property(nonatomic) CGFloat restoredRailLastWidth;
@property(nonatomic) BOOL splitLayout;
- (void)touchColumn;
@property(nonatomic, strong) UIVisualEffectView *railMaterial;
@property(nonatomic, copy) NSString *watchedFloating;
// Previous keyboard state, so refresh can spot the up/down edges.
@property(nonatomic) BOOL keyboardUp;
- (void)refresh;
- (void)scheduleAutoCollapse;
- (void)resetAutoCollapseTimer;
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
- (UIView *)rail:(NFBRail *)rail bubbleAtPoint:(CGPoint)point withEvent:(UIEvent *)event;
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

@implementation NFBManager {
    // C structs as ivars, not properties: a property getter returns a temporary,
    // so `self.x.field = NO` would not compile and `&self.x` would be the address
    // of that temporary. An ivar also keeps this state out of any class
    // extension, which may only hold declarations.
    NFBProbeStamp floatingProbe;
    NFBProbeStamp desktopProbe;
    // The 2 Hz tick's previous pass, compared by NFBTickNeedsLayout.
    NFBTickState tickState;
}
// Only a collapsed column hugs the screen edge; an expanded one stays
// visible, which is what a left swipe unfolds into.
static BOOL edgeRailHugging(BOOL halfHidden, BOOL expanded) {
    return halfHidden && !expanded;
}
// Longest a reordering dedupe may postpone a full layout. Short enough that an
// external badge clear is still gone within one user-visible beat, long enough
// that the tick stays a 2 Hz state check instead of a 20 Hz layout.
static const CFTimeInterval kTickReconcileInterval = 2.0;
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
        _pendingBurstApps = [NSMutableSet set];
        _retracting = [NSMutableSet set];
        _dismissedSwitcher = [NSMutableSet set];
        _closingApps = [NSMutableSet set];
        _generations = [NSMutableDictionary dictionary];
        _lastBadges = [NSMutableDictionary dictionary];
        _badgeCounts = [NSMutableDictionary dictionary];
        _lastBadgeVersion = [NSMutableDictionary dictionary];
        _gestureTimes = [NSMutableDictionary dictionary];
        _retractTokens=[NSMutableDictionary dictionary];
        _railStateStore = [NFBRailStateStore new];
        // The window does not exist yet: the committed column state is "shown",
        // so the first request explores the normal reveal path.
        _columnTargetOffscreen = NO;
        _columnParkedEver = NO;
        [self restoreRailMetric];
        __weak NFBManager *weakSelf = self;
        NFBKeyboardInstall(^{ [weakSelf setNeedsRefresh]; });
        [self reloadPreferences];
    }
    return self;
}
// The column reuses the split's top edge and icon size in fullscreen, and those
// lived in memory only - so after a SpringBoard relaunch the first layout fell
// back to the settings top and the control sat in the top-right corner until a
// split had been opened once. Read the persisted geometry once, on the main
// thread, before the first layout runs.
- (void)restoreRailMetric {
    self.restoredRailMetricValid = NO;
    NFBRailMetric stored = [self.railStateStore loadMetric];
    if (!NFBRailMetricUsable(stored, stored.screenWidth)) return;
    self.restoredRailMetric = stored;
    self.restoredRailMetricValid = YES;
    self.splitRailTop = stored.top;
    self.splitRailDiameter = stored.diameter;
    self.splitRailScreenWidth = stored.screenWidth;
    self.splitRailMeasured = YES;
    self.restoredRailLastWidth = stored.screenWidth;
}

// Switches the restored metric off as soon as the screen shape changes: the
// cached top is only meaningful on the width it was measured on, so a rotation
// must fall back to a fresh measurement (and the settings size) rather than mix
// a stale anchor into a different screen.
- (void)invalidateRestoredRailMetricForSize:(CGSize)size {
    if (!self.restoredRailMetricValid) return;
    if (self.restoredRailLastWidth == size.width) return;
    self.restoredRailLastWidth = size.width;
    if (!NFBSplitMetricsValid(self.restoredRailMetric.diameter, 0, size.width,
            self.restoredRailMetric.screenWidth)) {
        self.restoredRailMetricValid = NO;
    }
}

- (void)persistRailMetricIfMeasured:(BOOL)measured {
    if (!measured) return;
    NFBRailMetric metric;
    metric.top = self.splitRailTop;
    metric.diameter = self.splitRailDiameter;
    metric.screenWidth = self.splitRailScreenWidth;
    [self.railStateStore scheduleMetric:metric after:NFBRailStateWriteDelay];
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
    // A burst posts several requests in a row. Each one used to run its own full
    // layout and then shake/scroll the bubble the *previous* layout had produced,
    // so the reminder fought the layout that was still moving the row. The apps
    // are collected and the burst is laid out once, on the next runloop turn; the
    // reminder effects then run from that pass, after it has placed the bubbles
    // (runBurstEffects), so a request arriving mid-layout just joins it.
    if (![self.pendingBurstApps containsObject:appID]) [self.pendingBurstApps addObject:appID];
    if (self.burstRefreshPending) return;
    self.burstRefreshPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBManager *manager = weakSelf;
        if (!manager) return;
        manager.burstRefreshPending = NO;
        // Also runs when the coalesced hook is already pending: it was scheduled
        // before this request, so it would commit the burst without laying it out.
        [manager refresh];
    });
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
    if (gesture.state != UIGestureRecognizerStateEnded || [self isLocked] || ![self acceptGestureForKey:@"clearAll"]) return;
    if (!NFBTrollVisibleApp().length) {
        // Outside a split this button clears the notification queue and folds the
        // list away; it is not a split-close action.
        [self.store clear];
        self.edgeExpanded = NO;
        [self refresh];
        return;
    }
    [self resetAutoCollapseTimer];
    NFBCloseDesktopSplit();
    // Fold to the collapsed state first so the column slides to the edge with the
    // split's own dismissal animation instead of snapping after it.
    if (self.edgeExpanded) {
        self.edgeExpanded = NO;
        [self refresh];
    }
    if (!NFBCloseCurrentSplit()) [self showOpenNotice:@"未能读取 TrollOpen 右侧区域的单击接口"];
    else NFBOpenEdgeAfterClose();
    [self refresh];
}
- (NFBActionMode)desktopActionMode {
    return NFBActionModeFor(self.splitLayout && self.desktopActionTarget != nil, self.edgeExpanded);
}
- (void)performDesktopAction:(NFBActionEffect)effect {
    switch (effect) {
        case NFBActionToggleSplit: {
            UIView *target = self.desktopActionTouchTarget;
            self.desktopActionTouchTarget = nil;
            if (!target || target != self.desktopActionTarget || target != NFBDesktopActionWindow()) { [self refresh]; return; }
            if (![self acceptGestureForKey:@"desktopAction"]) return;
            if (!NFBShowDesktopInSplit(target)) [self showOpenNotice:NFBDesktopSplitError()];
            [self refresh];
            return;
        }
        case NFBActionOpenConsole: {
            UIView *target = self.desktopActionTouchTarget;
            self.desktopActionTouchTarget = nil;
            if (!target || target != self.desktopActionTarget || target != NFBDesktopActionWindow()) { [self refresh]; return; }
            if (![self acceptGestureForKey:@"desktopConsole"]) return;
            NFBCloseDesktopSplit();
            if (!NFBOpenNativeConsole()) [self showOpenNotice:@"Open 控制台入口不可用，请确认使用适配的定制版 1.3.7"];
            [self refresh];
            return;
        }
        case NFBActionFoldColumn:
            // The tap keeps its existing toggle; only the swipe is one-way.
            self.desktopActionTouchTarget = nil;
            self.edgeExpanded = NO;
            [self scheduleAutoCollapse];
            [self refresh];
            return;
        case NFBActionUnfoldColumn:
            self.desktopActionTouchTarget = nil;
            self.edgeExpanded = YES;
            [self scheduleAutoCollapse];
            [self refresh];
            return;
        case NFBActionClearUnread:
            self.desktopActionTouchTarget = nil;
            [self clearUnreadKeepingExpanded];
            // No unread count, no X: the app buttons themselves stay, and the
            // open column keeps its own real 5s clock instead of folding at once.
            if (self.edgeExpanded) [self holdClearedColumnAndRestartClock];
            return;
        case NFBActionNone:
            break;
    }
    [self refresh];
}
- (void)desktopActionTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !self.enabled || [self isLocked]) return;
    [self performDesktopAction:NFBActionEffectFor([self desktopActionMode], NFBActionTap, YES, NO)];
}
- (void)desktopActionHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !self.enabled || [self isLocked]) return;
    // The expanded hold clears unread and counts as a real interaction even if
    // the clear is then refused; the split house button is unchanged.
    if ([self desktopActionMode] == NFBActionModeExpanded) [self touchColumn];
    [self performDesktopAction:NFBActionEffectFor([self desktopActionMode], NFBActionHold, YES, NO)];
}
- (void)desktopActionSwiped:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !self.enabled || [self isLocked]) return;
    if (gesture.direction != UISwipeGestureRecognizerDirectionLeft) return;
    [self performDesktopAction:NFBActionEffectFor([self desktopActionMode], NFBActionSwipeLeft, YES, NO)];
}
// Long press on the expanded fullscreen control: drop what the bubbles count as
// unread (and their badges) without touching the apps, the app switcher, the
// system Notification Centre, or the column itself. Only the store's records go,
// so pins/order and the background apps that make up the list stay put.
//
// Keeping those rows takes two steps. The clear's own refresh must not rebuild
// them from the now-empty unread list (holdsClearedColumn), and a cleared column
// has no X, so no later refresh would stamp the clock: the hold stamps it once,
// with no unread left the column would otherwise fold on the next tick.
- (void)holdClearedColumnAndRestartClock {
    self.holdsClearedColumn = YES;
    [self refresh];
    self.holdsClearedColumn = NO;
    [self scheduleAutoCollapse];
}
- (void)clearUnreadKeepingExpanded {
    if (![self acceptGestureForKey:@"desktopUnread"]) return;
    [self.store clearUnreadRecords];
    // The record waiting for its bubble has no queued entry, so the store cannot
    // drop it; releasing it here keeps the badge from reappearing.
    self.pendingRecord = nil;
    // Stay expanded; the effect keeps the rows and stamps the 5s clock.
    self.edgeExpanded = YES;
}
- (void)layoutDesktopAction:(CGRect)frame target:(UIView *)target split:(BOOL)splitNow toggleFrame:(CGRect)toggleFrame duration:(NSTimeInterval)duration {
    // This slot does double duty: in a split it is the desktop button, outside one
    // it is the collapse/expand control for the column. Same position, same size,
    // so the two never compete for space.
    // Explicit state, not a guess from the target: while Open rebuilds its window
    // the split has no target for a moment, and inferring from `!target` turned
    // the desktop button into a collapse control mid-split.
    BOOL toggleMode = !splitNow && !CGRectIsNull(toggleFrame) && toggleFrame.size.width > 0;
    if (toggleMode) frame = toggleFrame;
    BOOL visible = ((target && !CGRectIsNull(frame) && !CGRectIsEmpty(frame)) || toggleMode) && self.enabled;
    self.desktopActionTarget = (target && !toggleMode) ? target : nil;
    if (!self.desktopActionButton && !visible) return;
    self.desktopActionToggle = toggleMode;
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
        // Left only: a right swipe must never fold or toggle the column.
        self.desktopActionSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(desktopActionSwiped:)];
        self.desktopActionSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
        self.desktopActionSwipe.delegate = self;
        [self.desktopActionTap requireGestureRecognizerToFail:self.desktopActionHold];
        [self.desktopActionTap requireGestureRecognizerToFail:self.desktopActionSwipe];
        // A refused swipe (expanded, split, locked) must leave the control as
        // free as before: it never claims a touch it does not act on.
        self.desktopActionSwipe.cancelsTouchesInView = NO;
        [button addGestureRecognizer:self.desktopActionHold];
        [button addGestureRecognizer:self.desktopActionSwipe];
        [button addGestureRecognizer:self.desktopActionTap];
        button.alpha = 0;
        self.desktopActionButton = button;
        // The control is carried by the window itself, not by the root view:
        // HideInScreenshots disables the whole root view's interaction (its alpha
        // is untouched), which silently swallowed every tap on the control. The
        // window's own hit test already drops touches that reach neither the
        // control nor a view of the root.
        [self.window addSubview:button];
        [self.window bringSubviewToFront:button];
    }
    NFBBubble *button = self.desktopActionButton;
    static UIImage *houseIcon, *chevronLeftIcon, *chevronRightIcon;
    if (!houseIcon) {
        houseIcon = [UIImage systemImageNamed:@"house.fill"];
        chevronLeftIcon = [UIImage systemImageNamed:@"chevron.left"];
        chevronRightIcon = [UIImage systemImageNamed:@"chevron.right"];
    }
    UIImage *glyph = houseIcon;
    UIColor *tint = UIColor.systemGreenColor;
    if (toggleMode) {
        glyph = self.edgeExpanded ? chevronRightIcon : chevronLeftIcon;
        tint = UIColor.systemBlueColor;
        button.accessibilityLabel = self.edgeExpanded ? @"收起图标列" : @"展开图标列";
        button.accessibilityHint = self.edgeExpanded ? @"单击收起通知图标列，长按清除未读与角标"
                                                     : @"单击或向左滑动展开通知图标列";
    } else {
        button.accessibilityLabel = @"显示桌面 / Open 控制台";
        button.accessibilityHint = @"单击显示或关闭桌面分屏，长按打开 Open 控制台";
    }
    if (button.imageView.image != glyph) button.imageView.image = glyph;
    if (!CGColorEqualToColor(button.imageView.tintColor.CGColor, tint.CGColor)) button.imageView.tintColor = tint;
    // Every recognizer stays enabled. A disabled hold would never fail, so the
    // tap's requireGestureRecognizerToFail would hold each tap for the press
    // duration; the delegate refuses the hold wherever it has no job instead.
    for (UIGestureRecognizer *recognizer in button.gestureRecognizers) recognizer.enabled = YES;
    // Parked: nothing else is on screen so the hidden column keeps only the
    // control, half off the right edge (origin.x = width - 7 - diameter/2) at half
    // opacity. An expanded column never parks, even with nothing to show.
    // Half hidden (collapsed fullscreen column): the control shares the rows'
    // shift and alpha, so the whole column reads as one state.
    BOOL fade = NFBToggleShouldFade(self.desktopActionParked, self.desktopActionHalfHidden);
    CGFloat targetAlpha = visible ? (fade ? 0.5 : 1) : 0;
    // On screen (or parked with a visible half) is enough: no desktop target needed.
    button.userInteractionEnabled = NFBToggleIsInteractive(self.enabled, visible, NO);
    BOOL appearing = visible && (button.alpha < 0.01 || CGRectIsEmpty(button.frame));
    if (appearing) button.frame = frame;
    [self.window bringSubviewToFront:button];
    CGFloat imageSide = visible ? MAX(1, frame.size.width - 14) : button.imageView.frame.size.width;
    // The 20 Hz passes used to submit this same curve every time. Only a pass
    // that really changes an animated value (or brings the control back) animates;
    // any other pass commits the values without a separate animation, so the style
    // and timing of a real move are untouched.
    NFBDesktopActionInput action = {appearing, button.frame.origin.x, button.frame.origin.y,
        button.frame.size.width, button.frame.size.height, frame.origin.x, frame.origin.y,
        frame.size.width, frame.size.height, button.alpha, targetAlpha,
        button.imageView.frame.size.width, imageSide};
    void (^applyAction)(void) = ^{
        button.alpha = targetAlpha;
        if (visible) {
            button.frame = frame;
            button.imageView.frame = CGRectMake(7, 7, imageSide, imageSide);
            // Identical shape in both modes: the toggle occupies the desktop
            // button's slot, so it must read as the same control.
            button.imageView.layer.cornerRadius = imageSide * 0.23;
        }
    };
    if (!NFBDesktopActionNeedsAnimation(action)) { applyAction(); return; }
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : MAX(0.16, duration)
        delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut animations:applyAction
    completion:nil];
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
    button.accessibilityTraits = UIAccessibilityTraitButton;
    if (!self.splitLayout) {
        // Fullscreen: the X only empties the notification queue. Its gestures are
        // unchanged (tap clears, long press clears the background), so only the
        // spoken description follows the new meaning.
        button.accessibilityLabel = @"清空通知";
        button.accessibilityHint = @"单击清空通知列表，长按清理后台";
        return;
    }
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
// Same-round probes (NFBProbePolicy.h). The 20 Hz entry points (watcher, tick,
// notification request) touch a fresh token for their turn; inside that turn both
// the entry point and any layout scheduled from it share one answer.
- (UIView *)desktopTargetProbe:(BOOL *)probed {
    UIView *target = NFBDesktopActionWindow();
    if (target) desktopProbe = NFBProbeRecord(desktopProbe, YES, (__bridge const void *)self.probeRoundToken, CACurrentMediaTime());
    else { desktopProbe = NFBProbeRecord(desktopProbe, NO, (__bridge const void *)self.probeRoundToken, CACurrentMediaTime()); }
    if (probed) *probed = YES;
    return target;
}
- (CGRect)splitFrameProbe:(BOOL *)probed {
    CGRect frame = NFBSplitFrameInView(self.window.rootViewController.view);
    BOOL usable = !CGRectIsNull(frame) && !CGRectIsEmpty(frame) && isfinite(CGRectGetMaxX(frame));
    // A null frame is recorded too: it belongs to this round and must not be
    // confused with a probe from an earlier one.
    floatingProbe = NFBProbeRecord(floatingProbe, usable, (__bridge const void *)self.probeRoundToken, CACurrentMediaTime());
    if (probed) *probed = YES;
    return frame;
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
// Split class availability is asked once per fire by floatingWatchFired, which
// drops every cached probe when the framework is not up yet (late retry); the
// body then reads that flag instead of asking a second time.
- (void)floatingWatchFired {
    // 20 Hz entry point on the SpringBoard main thread: one uncaught exception
    // from any private call below takes the whole process down.
    // A nil split class means the framework was not up yet when the class was
    // resolved: reset the cached stamp so the next fire probes again (late retry)
    // instead of reusing an answer that was never taken.
    BOOL classWasMissing = NFBSplitFrameClassUnavailable();
    self.floatingWatchClassMissing = classWasMissing;
    if (classWasMissing) {
        floatingProbe.resolved = NO; floatingProbe.usable = NO;
        desktopProbe.resolved = NO; desktopProbe.usable = NO;
        self.desktopProbeLateRetry = CACurrentMediaTime() + NFBProbeLateRetry;
    }
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
    // One 20 Hz fire is one probe round: a layout submitted from this fire (and
    // the one running right now) shares these answers instead of probing twice.
    // The 20 Hz period itself, the explicit invalidation on a nil class and the
    // late retry are unchanged.
    self.probeRoundToken = [NSObject new];
    NSString *now = NFBSplitAttachmentApp();
    // syncFloatingWatch only keeps this timer alive while an attachment is
    // reported, so there is no idle rate to save here: arriving without one
    // means it was just dismissed, and halving the rate would only delay that.
    NSString *currentApp = NFBTrollVisibleApp();
    // Orientation can change while app identity and window frame stay the same.
    NSString *switchApp = [self.retracting containsObject:currentApp ?: @""] ? nil : currentApp;
    NFBObserveSplitSwitch(switchApp, self.enabled && self.closePreviousSplit);
    CGRect frame = [self splitFrameProbe:NULL];
    BOOL sameFrame = CGRectEqualToRect(frame, self.observedSplitFrame) ||
        (CGRectIsNull(frame) && CGRectIsNull(self.observedSplitFrame));
    UIView *actionTarget = nil;
    const void *round = (__bridge const void *)self.probeRoundToken;
    BOOL reusedDesktop = currentApp.length &&
        NFBProbeReusable(desktopProbe, round, self.desktopProbeLateRetry, CACurrentMediaTime());
    if (currentApp.length) {
        if (reusedDesktop) actionTarget = NFBDesktopActionWindow();
        else actionTarget = [self desktopTargetProbe:NULL];
    }
    CGRect actionFrame = NFBWindowFrameInView(actionTarget, self.window.rootViewController.view);
    BOOL sameActionFrame = CGRectEqualToRect(actionFrame, self.observedActionFrame) ||
        (CGRectIsNull(actionFrame) && CGRectIsNull(self.observedActionFrame));
    if (self.floatingWatchClassMissing) {
        // Nothing could be read this fire; the next one probes again.
        return;
    }
    if ((now == self.watchedFloating || [now isEqualToString:self.watchedFloating]) && sameFrame &&
        actionTarget == self.observedActionTarget && sameActionFrame) return;
    self.observedActionTarget = actionTarget; self.observedActionFrame = actionFrame;
    self.observedSplitFrame = frame;
    self.watchedFloating = now;
    [self refreshIfNeeded];
}

- (void)tick {
    if (!self.enabled) return;
    // Same reasoning as floatingWatchFired: private SpringBoard calls here must
    // never propagate out into the runloop.
    @try { [self tickBody]; }
    @catch (NSException *error) { NFBErrorLog(@"tick failed: %@", error); }
}
- (void)tickBody {
    // The 2 Hz tick no longer submits a layout when nothing it can see changed.
    // Every state the layout reads is gathered below into one NFBTickState and
    // compared by NFBTickNeedsLayout; a change there still runs the same full
    // layout. The split watcher keeps its own 20 Hz passes on top of this, and a
    // probe cached inside this round is shared rather than repeated.
    self.probeRoundToken = [NSObject new];
    // Bounded reconciliation: what the comparison below cannot see (a badge that
    // changed outside our records, a system-side withdraw) gets a full layout at
    // least every kTickReconcileInterval. `lastLayoutAt` is written only by a pass
    // that really laid the column out, so a skipped or early-returned pass cannot
    // postpone the backstop forever.
    CFTimeInterval tickNow = CACurrentMediaTime();
    BOOL reconcileDue = tickNow - self.lastLayoutAt >= kTickReconcileInterval;
    // A pass that did not really lay the column out (disabled, lock screen,
    // keyboard) is retried on the next tick: otherwise a coalesced tick could
    // leave lastLayoutAt fresh over a layout that never happened.
    BOOL reconcile = reconcileDue || !self.lastRefreshComplete;
    // Any pass that has actually completed (gesture, burst, watcher, probe) also
    // counts, so the backstop is "no full layout for 2s" rather than "no tick-
    // requested layout for 2s": a busy column that lays out every turn needs none.
    if (self.lastRefreshComplete && tickNow - self.lastLayoutAt < kTickReconcileInterval)
        reconcile = NO;
    // Auto-fold applies to the expanded fullscreen column only; a split column is
    // driven by the floating window and must never time out.
    BOOL collapseDue = NO;
    // The split guard stays on the stamp itself: nothing is touched while split.
    if (self.edgeExpanded && !self.splitLayout && tickNow - self.lastInteractionAt > 5.0) {
        self.edgeExpanded = NO;
        // Folding is not an interaction, but it ends this countdown: without a
        // fresh stamp the next expand would fold on its very first tick.
        self.lastInteractionAt = tickNow;
        [self refresh];
        return;
    }
    // Once the countdown has run out the fold must still reach a layout that is
    // submitted, so the layout is requested on every tick until it has folded (an
    // unchanged state is otherwise allowed to skip the layout).
    collapseDue = self.edgeExpanded && !self.splitLayout;
    // `dirty` starts as exactly that: the fold still owed, which no state
    // comparison can see (this tick's own edgeExpanded is already folded).
    BOOL dirty = collapseDue;
    BOOL locked = [self isLocked];
    self.tickActiveFloating = NFBTrollVisibleApp();
    // Resolve the window state once per tick: the frontmost app, the home screen
    // and the split all come from the same main-queue snapshot, so an unreadable
    // front app can never be reported as "home" by a second lookup. The snapshot
    // only lives for this runloop turn and -refresh rebuilds it, so nothing is
    // cached across ticks.
    NFBInvalidateWindowState();
    NFBWindowState *tickWindow = NFBCurrentWindowState();
    long tickUnread = 0;
    for (NSString *appID in self.store.appIDs) tickUnread += (long)[self.store countForApp:appID];
    NSString *desktopFailure = NFBConsumeDesktopSplitFailure();
    if (desktopFailure.length) [self showOpenNotice:desktopFailure];
    if (self.pendingRecord) {
        NSString *front = NFBFrontmostAppID();
        if (![self isLocked] && [front isEqual:self.pendingRecord.appID]) {
            [self.store consumeRecord:self.pendingRecord]; self.pendingRecord = nil;
        } else if (CACurrentMediaTime() > self.pendingUntil) self.pendingRecord = nil;
    }
    // What this tick knows that a layout would read. A full layout is only needed
    // when one of these really changed (or an edge is due); otherwise the state
    // is still checked here every 0.5s. Nothing is cached across a change: every
    // state below is re-read, and the ones not re-read here are in NFBTickState.
    // Note `dirty` already holds the owed fold from above.
    NSString *watched = self.watchedFloating;
    NSString *floatingNow = self.tickActiveFloating;
    if (!(watched && floatingNow && [watched isEqualToString:floatingNow])) dirty = YES;
    // Do not interpret a temporarily inaccessible switcher on the lock screen as empty.
    if (!locked) {
        NSArray *current = NFBReadSwitcherApps();
        if (current) {
            NSSet *set = [NSSet setWithArray:current];
            [self.dismissedSwitcher intersectSet:set];
            if (current.count == 0 && self.lastSwitcher.count > 0) {
                // Require two consecutive empty reads to reject intermediate snapshots.
                if (++self.emptyReads >= 2) {
                    [self closeAppsInOrder:[self orderedAppsForRemoval]];
                    self.lastSwitcher = current; self.emptyReads = 0;
                    dirty = YES;
                }
            } else {
                self.emptyReads = 0;
                NSSet *oldSet = [NSSet setWithArray:self.lastSwitcher ?: @[]];
                NSMutableArray *removed = [NSMutableArray array];
                for (NSString *app in self.store.appIDs)
                    if ([oldSet containsObject:app] && ![set containsObject:app]) [removed addObject:app];
                if (removed.count) { [self closeAppsInOrder:removed]; dirty = YES; }
                for (NSString *app in current) {
                    // A new card in the switcher is the "external badge" edge: the app
                    // gained a background card outside the plugin.
                    if (![oldSet containsObject:app]) dirty = YES;
                    if (![oldSet containsObject:app])
                        self.generations[app] = @([self.generations[app] unsignedIntegerValue] + 1);
                    if (![self.dismissedSwitcher containsObject:app] && ![self.store.appIDs containsObject:app]) {
                        [self.store pinApp:app];
                        self.generations[app] = @([self.generations[app] unsignedIntegerValue] + 1);
                        dirty = YES;
                    }
                }
                if (![current isEqualToArray:self.lastSwitcher ?: @[]]) dirty = YES;
                self.lastSwitcher = current;
            }
        }
    } else if (!self.lastLocked) {
        dirty = YES;   // entered the lock screen: the column must step aside
    }
    self.lastLocked = locked;
    // A keyboard pulls the whole column offscreen, so its state is compared
    // explicitly instead of guessing from the property the last layout stored.
    BOOL keyboard = NFBKeyboardVisible();
    NSString *tickFront = tickWindow ? tickWindow.frontApp : NFBFrontmostAppID();
    NFBTickState current;
    current.front = tickFront.UTF8String;
    // Only a real home-screen read counts as home; an unreadable state is not one.
    current.home = tickWindow && tickWindow.home;
    current.unread = tickUnread;
    current.locked = locked;
    current.keyboard = keyboard;
    current.expanded = self.edgeExpanded;
    current.split = self.splitLayout;
    current.incomplete = self.layoutRecording;
    // Same value the capture flag was last written with (see -refresh).
    current.captureHidden = self.hideInScreenshots;
    // The comparison is the only thing that notices front app / home / badge
    // changes when no notification or gesture arrives: nothing else in the tick
    // looks at them, so they are part of NFBTickNeedsLayout and tested there. The
    // backstop above is the belt to this comparison's braces.
    BOOL needs = NFBTickNeedsLayout(self.tickStateValid ? &tickState : NULL, &current,
                                    dirty || self.tickForcedRefresh || reconcile, NO);
    tickState = current;
    self.tickStateValid = YES;
    if (needs) {
        self.tickForcedRefresh = NO;
        [self refreshIfNeeded];
    }
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
    // A half-hidden row hangs past the clip; the rail must still offer that row's
    // on-screen part to hit testing (see -rail:bubbleAtPoint:withEvent:).
    self.rail.clipsToBounds = NO;
    self.rail.nfbHitDelegate = self;
    self.rail.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    // The window is the full screen, so this clip is the physical screen edge: a
    // half-hidden column may extend past it and is cropped there, never earlier.
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
    // Text only: -layoutBadge:diameter: owns the geometry for all call sites.
    // The version changes only with the content, so a 20 Hz pass that repeats the
    // same count never restarts the badge animation.
    NSNumber *previousCount = self.badgeCounts[button.appID];
    if (NFBBadgeNeedsAnimation(button.badge.text.length > 0, text.length > 0,
            previousCount ? previousCount.doubleValue : NAN, (double)unread))
        button.badgeContentVersion++;
    self.badgeCounts[button.appID] = @(unread);
    button.badge.hidden = !text.length;
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
    if (self.refreshScheduled || self.layoutRecording) return;
    self.refreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NFBManager *manager = weakSelf;
        if (!manager) return;
        manager.refreshScheduled = NO;
        [manager refresh];
    });
}
// Layout entry point for the 20 Hz callers (watcher, tick, burst): when a full
// layout is already running this turn the request is satisfied by it, because the
// next pass checks the same state again.
- (void)refreshIfNeeded {
    if (self.layoutRecording) { self.refreshScheduled = YES; return; }
    [self refresh];
}
// Runs after the burst layout placed its bubbles. Membership decides whether the
// reminder still applies (the app may have been closed by that same pass), and
// the order follows the row the layout produced, never set enumeration order.
- (void)runBurstEffects {
    if (!self.pendingBurstApps.count) return;
    NSArray<NSString *> *order = [self.lastLayoutApps ?: @[] arrayByAddingObjectsFromArray:self.favoriteApps ?: @[]];
    NSMutableArray<NSString *> *targets = [NSMutableArray array];
    // Membership and order are decided first: the scroll below delivers its
    // Change notification synchronously, and a request delivered from there must
    // not be able to lose its reminder.
    for (NSString *app in order)
        if ([self.pendingBurstApps containsObject:app] && ![targets containsObject:app]) [targets addObject:app];
    BOOL inSplit = NFBTrollVisibleApp().length > 0;
    for (NSString *appID in targets) {
        NFBBubble *button = self.buttons[appID] ?: self.favoriteButtons[appID];
        UIScrollView *owner = [button.superview isKindOfClass:UIScrollView.class] ? (UIScrollView *)button.superview : nil;
        CGRect row = owner ? CGRectMake(0, button.center.y - button.bounds.size.height / 2, owner.bounds.size.width, button.bounds.size.height) : CGRectZero;
        NFBBurstEffectInput in = {
            !self.window.hidden,
            button != nil && owner != nil,
            inSplit,
            [appID isEqualToString:NFBClearAllID],
            UIAccessibilityIsReduceMotionEnabled(),
            owner ? CGRectIntersectsRect(owner.bounds, row) : false
        };
        // New message while an app sits in the split view: shake that bubble as
        // a reminder. Unchanged condition, now on a row that is really placed.
        if (NFBBurstShouldShake(in)) [self shakeBubble:button];
        if (!owner) continue;
        [owner scrollRectToVisible:row animated:!in.reduceMotion];
    }
    // Dropped only now, and only the apps this pass handled. An app without a
    // bubble after the layout (closed meanwhile) has no reminder left either.
    for (NSString *appID in targets) [self.pendingBurstApps removeObject:appID];
    for (NSString *appID in [self.pendingBurstApps allObjects])
        if (!self.buttons[appID] && !self.favoriteButtons[appID]) [self.pendingBurstApps removeObject:appID];
}
// Single source of truth for the unread badge: anchored to the icon's top-right,
// sized from the actual glyph width, never wider than the icon itself.
- (void)layoutBadge:(NFBBubble *)button diameter:(CGFloat)diameter {
    UILabel *badge = button.badge;
    if (!badge) return;
    // The count sits inside the icon's own top-left corner. The rect is derived
    // from imageView.frame, so it can never leave the image (and therefore never
    // hangs over the screen edge on a half-hidden row), and the width is clamped to
    // the diameter: a long count shrinks the text, it never squashes the icon.
    CGRect image = button.imageView.frame;
    CGFloat side = fmin(CGRectGetWidth(image), CGRectGetHeight(image));
    if (!(side > 1)) {
        image = CGRectMake(7, 7, diameter, diameter);
        side = diameter;
    }
    CGSize text = CGSizeZero;
    if (badge.text.length)
        text = [badge.text sizeWithAttributes:@{NSFontAttributeName: badge.font ?: [UIFont boldSystemFontOfSize:12]}];
    NFBBadgeRect layout = NFBBadgeFrame(CGRectGetMinX(image), CGRectGetMinY(image), side, diameter,
        text.width, badge.text.length > 0);
    CGRect frame = CGRectMake(layout.x, layout.y, layout.width, layout.height);
    if (CGRectGetWidth(frame) <= 0 || CGRectGetHeight(frame) <= 0) return;
    if (!CGRectEqualToRect(badge.frame, frame)) badge.frame = frame;
    CGFloat radius = frame.size.height / 2;
    if (fabs(badge.layer.cornerRadius - radius) > 0.01) badge.layer.cornerRadius = radius;
    UIFont *font = [UIFont boldSystemFontOfSize:MIN(12, frame.size.height * 0.62)];
    if (fabs(badge.font.pointSize - font.pointSize) > 0.01) badge.font = font;
    if (!badge.adjustsFontSizeToFitWidth) badge.adjustsFontSizeToFitWidth = YES;
    if (fabs(badge.minimumScaleFactor - 0.6) > 0.001) badge.minimumScaleFactor = 0.6;
}
// The column is a window, so `hidden` cannot be animated (it switches the render
// tree off between frames). Translate the root view instead and only flip
// `hidden` once the slide has finished.
// Expanded lists fold themselves away after five seconds without interaction.
// A timestamp checked by the existing 2 Hz tick avoids rebuilding a timer on
// every scroll callback.
- (void)scheduleAutoCollapse {
    self.lastInteractionAt = CACurrentMediaTime();
}
// Every genuine touch on the column restarts the five-second countdown.
- (void)touchColumn {
    // Stamped unconditionally: a touch in the very frame that expands the column
    // ran before edgeExpanded flipped, so the guard dropped its stamp and the
    // column folded again on the next tick.
    self.lastInteractionAt = CACurrentMediaTime();
}
- (void)resetAutoCollapseTimer {
    self.lastInteractionAt = CACurrentMediaTime();
}

- (void)setColumnOffscreen:(BOOL)offscreen {
    UIView *root = self.window ? self.window.rootViewController.view : nil;
    if (!root) { self.window.hidden = offscreen; return; }
    // iOS 26 previews the destination state while a slide runs, so a 20 Hz
    // `refresh` that re-asks for a slide already in flight (or already committed)
    // used to resubmit it every pass and the column flashed. Only a request that
    // changes the committed state starts anything; while a slide is in flight a
    // request for the *other* direction reverses it from the current position.
    // (This read is also what keeps `columnSliding` a decision, not write-only
    // state - test_objc_guards.py rule 4.)
    BOOL idle = NFBColumnMotionIdle(self.columnSliding, self.columnTouchesKnown,
                                   CGAffineTransformIsIdentity(root.transform),
                                   self.columnParked, self.window.hidden);
    if (!NFBColumnSlideNeeded(offscreen, self.columnTargetOffscreen)) {
        // The state on screen is already the one asked for. Reconcile a screen
        // that disagrees (an interrupted commit) without animating it back.
        if (idle) {
            root.transform = CGAffineTransformIdentity;
            self.window.hidden = offscreen;
        }
        return;
    }
    BOOL animated = !UIAccessibilityIsReduceMotionEnabled();
    CGFloat width = CGRectGetWidth(root.bounds);
    if (!(width > 0)) width = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGAffineTransform away = CGAffineTransformMakeTranslation(width, 0);
    self.columnTouchesKnown = animated;
    self.columnTargetOffscreen = offscreen;
    if (!animated) {
        root.transform = CGAffineTransformIdentity;
        self.window.hidden = offscreen;
        self.columnSliding = NO;
        self.columnParked = offscreen;
        return;
    }
    self.columnSliding = YES;
    // Interruption-safe: a completion from an earlier slide must never hide or
    // reveal the column the current slide is moving.
    NSUInteger token = ++self.columnSlideToken;
    NSPointerArray *column = [NSPointerArray weakObjectsPointerArray];
    [column addPointer:(__bridge void *)root];
    if (offscreen) {
        [UIView animateWithDuration:0.24 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
            animations:^{ root.transform = away; }
            completion:^(__unused BOOL finished) {
                if (!NFBColumnCompletionApplies(token, self.columnSlideToken, self.columnTargetOffscreen, YES)) return;
                UIView *view = [column pointerAtIndex:0];
                // A finished animation leaves the transform at the model value; a
                // tree rebuilt meanwhile does not, and parking `hidden` on top of
                // a live transform is what made the next reveal jump.
                if (!NFBColumnTransformMatches(CGAffineTransformIsIdentity(view.transform), NO)) return;
                view.transform = CGAffineTransformIdentity;
                self.window.hidden = YES;
                self.columnSliding = NO;
                self.columnParked = YES;
            }];
    } else {
        self.window.hidden = NO;
        // Start from the right edge only when the column was actually parked
        // there; reversing mid-slide (or a column that was merely not laid out
        // yet) continues from the current position instead of snapping away.
        // The first reveal of a fresh column (never parked, no layout yet) enters
        // from the edge as it always has; later ones only when truly parked.
        BOOL identity = CGAffineTransformIsIdentity(root.transform);
        if (!self.columnParkedEver && identity) {
            self.columnParkedEver = YES;
            self.columnTouchesKnown = YES;
            self.columnParked = YES;
        }
        if (NFBColumnRevealStartAway(self.columnTouchesKnown, self.columnParked, identity))
            root.transform = away;
        self.columnParked = NO;
        [UIView animateWithDuration:0.28 delay:0.04
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
            animations:^{ root.transform = CGAffineTransformIdentity; }
            completion:^(__unused BOOL finished) {
                if (!NFBColumnCompletionApplies(token, self.columnSlideToken, self.columnTargetOffscreen, NO)) return;
                UIView *view = [column pointerAtIndex:0];
                if (!NFBColumnTransformMatches(CGAffineTransformIsIdentity(view.transform), YES)) return;
                self.window.hidden = NO;
                self.columnSliding = NO;
            }];
    }
}

- (void)refresh {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    self.refreshScheduled = NO;
    self.layoutRecording = YES;
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
    // The column is being laid out now, so the frame the watcher remembers must be
    // this pass's, not the one from before it. Only a usable frame is stored: a
    // missing split frame stays NULL so the watcher asks again next fire instead of
    // treating a transient absence as "known". The target is not touched here - a
    // nil lookup may be a window being rebuilt, and the watcher must retry it.
    if (floatingApp.length) {
        CGRect probedFrame = NFBSplitFrameInView(self.window.rootViewController.view);
        self.observedSplitFrame = (!CGRectIsNull(probedFrame) && !CGRectIsEmpty(probedFrame))
            ? probedFrame : CGRectNull;
    }
    // A keyboard outranks everything else: typing is the one moment the bubbles
    // must be out of the way, so it pulls them all back in no matter what. The
    // ones it pulled in are remembered and popped back out the moment typing
    // ends (split-view bubbles come back on their own via floatingApp below).
    BOOL previousKeyboardUp = self.keyboardUp;
    BOOL keyboardUp = NFBKeyboardVisible();
    self.keyboardUp=keyboardUp;
    BOOL home = NFBCurrentWindowState().home;
    // Outside a split the column has two states: collapsed (only apps with unread
    // notifications) and expanded (everything, auto-collapses after 5s).
    BOOL split = floatingApp.length > 0;
    BOOL collapsed = !split && !self.edgeExpanded;
    // Frontmost fullscreen app. The resolved window state is built once per main
    // runloop turn and shared, so this is a lookup, not an extra tree scan. A
    // split owns the column, and the desktop owns no app, so neither qualifies.
    NFBWindowState *windowState = NFBCurrentWindowState();
    // The collapsed edge column keeps the existing recent-background group on
    // both the desktop and fullscreen apps. No special current-app membership.
    BOOL halfHiddenColumn = collapsed && !split;
    NSString *active = NFBTrollVisibleApp() ?: floatingApp ?: (home ? nil : windowState.frontApp);
    // Clearing unread must leave the column (and its background apps) exactly as
    // it was, so this one layout keeps the apps it is replacing until the
    // expanded hold has cleared. Pins and the app order live in the store and are
    // never touched; only the unread records go.
    if (self.holdsClearedColumn) {
        [apps removeAllObjects];
        [apps addObjectsFromArray:self.lastLayoutApps ?: @[]];
        [apps removeObject:NFBClearAllID];
    }
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
    NSMutableOrderedSet *history = [NSMutableOrderedSet orderedSetWithArray:self.recentUsedApps];
    [history addObjectsFromArray:self.lastSwitcher ?: @[]];
    // Apps that actually have queued notifications.
    NSMutableArray<NSString *> *notified = [NSMutableArray array];
    for (NSString *app in apps)
        if ([self.store countForApp:app] > 0 && ![self.closingApps containsObject:app]) [notified addObject:app];
    self.notifiedCount = notified.count;
    // Unread apps first (including unread favorites, which stay in the main
    // column even though the favorites rail is hidden), then the split's recent
    // background apps.
    NSMutableOrderedSet<NSString *> *columnApps = [NSMutableOrderedSet orderedSetWithArray:notified];
    // Reuse the very same recent-background group in every state. The ordered
    // set merges unread membership without duplicating an app or changing order.
    NSMutableArray<NSString *> *background = [NSMutableArray array];
    for (NSString *app in apps)
        if ([self.lastSwitcher containsObject:app] || [app isEqual:active]) [background addObject:app];
    [columnApps addObjectsFromArray:NFBRecentBackgroundThree(background, history.array, self.favoriteApps)];
    NSArray<NSString *> *railApps = columnApps.array;
    NSMutableArray<NSString *> *displayApps = [railApps mutableCopy];
    // The bottom close control belongs to split mode only. Outside a split,
    // clearing unread is the top control's hold gesture, regardless of count.
    BOOL showClearAll = NFBBottomCloseVisible(split);
    if (showClearAll) [displayApps addObject:NFBClearAllID];
    BOOL orderChanged = ![self.lastLayoutApps isEqualToArray:displayApps];
    self.lastLayoutApps = [displayApps copy];
    for (NSString *appID in self.buttons.allKeys) {
        if ([displayApps containsObject:appID]) continue;
        NFBBubble *button = self.buttons[appID];
        [self.buttons removeObjectForKey:appID];
        button.userInteractionEnabled = NO;
        if (!split && [appID isEqualToString:NFBClearAllID]) {
            // Do not leave a fading close key or its hit area behind outside a
            // split. Its previous animation must not re-expose it afterwards.
            [button.layer removeAllAnimations];
            button.hidden = YES;
            [button removeFromSuperview];
            continue;
        }
        unsigned long long removalToken = button.badgeContentVersion + 1;
        button.badgeContentVersion = removalToken;
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
            // otherwise a returning notification authors a second bubble. The
            // token additionally protects an interrupted removal that was reused.
            if (self.buttons[appID] != button && self.favoriteButtons[appID] != button &&
                NFBMotionCompletionIsCurrent(removalToken, button.badgeContentVersion))
                [button removeFromSuperview];
        }];
    }
    // True only for the paths (disabled / lock / keyboard) that return before the
    // column is actually laid out. Everything after them sets the no-return case
    // on the way out, so this one write covers every "did not really lay out".
    BOOL laidOut = NO;
    if (!self.enabled) {
        NFBUpdateOpenEdgeSplitIconsVisible(NO);
        NSUInteger presentationEpoch=self.presentationEpoch;
        // Delay hiding until the removal animation completes; recheck new arrivals.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.presentationEpoch==presentationEpoch && !self.enabled) self.window.hidden = YES;
        });
        self.layoutRecording = NO;
        return;
    }
    if (![self shouldShow]) {
        NFBUpdateOpenEdgeSplitIconsVisible(NO); self.window.hidden = YES;
        self.layoutRecording = NO;
        return;
    }
    // A keyboard owns the space this column would occupy. Letting it stay on
    // screen left the material strip painted in the top-right corner while the
    // icons themselves collapsed, which reads as a stray shadow, so the column
    // slides out while typing and slides back when the keyboard goes away.
    if (keyboardUp) {
        [self setColumnOffscreen:YES];
        self.layoutRecording = NO;
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

    BOOL attachmentChanged = attached != self.splitRailActive;
    self.splitRailActive = attached;
    // One geometry source for both modes. `split` here is the resolved, real split
    // state, never a guess from the desktop target (nil while Open rebuilds). The
    // frame is sanitised first, so usableSplit can be evaluated before any use.
    CGRect splitA = CGRectIsNull(splitFrame) ? CGRectZero : splitFrame;
    if (!isfinite(splitA.origin.x) || !isfinite(splitA.origin.y) ||
        !isfinite(splitA.size.width) || !isfinite(splitA.size.height)) splitA = CGRectZero;
    BOOL usableSplit = isfinite(CGRectGetMaxX(splitA)) && isfinite(CGRectGetMaxY(splitA)) &&
        CGRectGetWidth(splitA) > 0 && CGRectGetHeight(splitA) > 0;
    BOOL splitNow = floatingApp.length > 0 && usableSplit;
    self.splitLayout = splitNow;
    NSUInteger notifiedCount = self.notifiedCount;
    // The hidden column has nothing to clear when no notification is queued, so
    // it keeps only the unread apps and the collapse control: no X, no favorites.
    BOOL hideFavorites = !(splitNow || self.edgeExpanded);
    BOOL collapse = !splitNow && !self.edgeExpanded;
    BOOL splitUsable = splitNow;
    NSUInteger columnRows = railApps.count;
    // The plan takes a platform-neutral inset struct; being field-compatible with
    // UIEdgeInsets means this stays a plain value copy.
    NFBRailInsets planSafe = { safe.top, safe.left, safe.bottom, safe.right };
    // A restored record only applies on the screen shape it was measured on; a
    // rotation or a different device drops it before the plan can reuse it.
    [self invalidateRestoredRailMetricForSize:bounds.size];
    NFBRailPlan plan = NFBPlanRail(bounds.size.width, bounds.size.height, planSafe, top, self.iconSize,
        NFBFloatingPosition, splitNow, splitA, splitUsable, self.verticalPosition, collapse,
        hideFavorites ? 0 : self.favoriteApps.count, (unsigned long)columnRows, (unsigned long)notifiedCount,
        (double)self.splitRailTop, (double)self.splitRailDiameter, (double)self.splitRailScreenWidth,
        self.splitRailMeasured, edgeRailHugging(halfHiddenColumn, self.edgeExpanded));
    // Keep the old fullscreen placement available if a device asks for it; the
    // default replays the measured split column (see NFBRailLayout.h).
    if (!splitNow && !NFBPreference(@"ColumnReuseSplitMeasure", YES))
        plan = NFBPlanRail(bounds.size.width, bounds.size.height, planSafe, top, self.iconSize,
            NFBFloatingPosition, NO, CGRectZero, NO, self.verticalPosition, collapse,
            hideFavorites ? 0 : self.favoriteApps.count, (unsigned long)columnRows,
            (unsigned long)notifiedCount, (double)self.splitRailTop, (double)self.splitRailDiameter,
            (double)self.splitRailScreenWidth, self.splitRailMeasured, edgeRailHugging(halfHiddenColumn, self.edgeExpanded));
    BOOL railMeasuredNow = NO;
    if (splitNow && plan.toggleTop > 0) {
        // A genuinely laid-out split column is the reference the fullscreen column
        // reuses: the same button-slot top (plan.toggleTop, not the content top one
        // row below it) and the diameter its actual space allowed. The slot top is
        // the only anchor that exists before any content row, so a very short
        // split window still records a usable value.
        self.splitRailTop = plan.toggleTop;
        self.splitRailDiameter = plan.diameter;
        self.splitRailScreenWidth = bounds.size.width;
        self.splitRailMeasured = YES;
        railMeasuredNow = YES;
    }
    [self persistRailMetricIfMeasured:railMeasuredNow];
    CGFloat diameter = plan.diameter;
    CGFloat side = diameter + 14;
    CGFloat step = diameter + 9;
    CGFloat height = CGRectGetHeight(plan.rail);
    CGRect railFrame = plan.rail;
    CGRect favoritesFrame = plan.favoritesVisible ? plan.favorites : CGRectZero;
    CGFloat clearCenterY = plan.clearCenterY;
    CGFloat railWidth = side;
    // One column width: the rail never widens, every row stays at side/2 in it.
    CGFloat railFrameWidth = CGRectGetWidth(railFrame);
    NSTimeInterval layoutDuration = UIAccessibilityIsReduceMotionEnabled() ? 0 : (attachmentChanged ? 0.35 : (splitNow ? 0.16 : NFBMotion));
    BOOL edgeMode = collapse;
    self.edgeMode = edgeMode;
    NSUInteger rowCount = columnRows;
    CGFloat contentHeight = rowCount ? (rowCount - 1) * step + side : 0;
    // Same-round reuse: when the watcher already probed in this round, this pass
    // reads its answer instead of asking SpringBoard again.
    BOOL reusedDesktop = NFBProbeReusable(desktopProbe, (__bridge const void *)self.probeRoundToken,
        self.desktopProbeLateRetry, CACurrentMediaTime());
    UIView *actionTarget = nil;
    if (floatingApp.length) {
        if (reusedDesktop) actionTarget = NFBDesktopActionWindow();
        else actionTarget = [self desktopTargetProbe:NULL];
    }
    // Both modes own the same top slot; the house button shows while a desktop
    // target exists, otherwise the collapse control covers it. The slot rect is
    // no longer zero in a split, which used to make the button disappear.
    CGRect desktopActionFrame = (splitNow && actionTarget) ? plan.toggle : CGRectNull;
    CGRect toggleFrame = (plan.toggleVisible && !splitNow) ? plan.toggle : CGRectNull;
    // The collapse control is a root-view sibling, not a rail child, so the plan's
    // shift for the rail has to be applied to it here: same shift as the rows, so
    // its image centre is the screen edge too. A split, an expanded column or a
    // parked-only column keep the plain slot.
    // Every gesture on the control (tap, hold, swipe) shares that visible half,
    // so a half-hidden control never claims the full square behind the edge.
    BOOL toggleHalfHidden = halfHiddenColumn && !self.edgeExpanded && !splitNow && !CGRectIsNull(toggleFrame);
    if (toggleHalfHidden) toggleFrame.origin.x = CGRectGetMinX(railFrame);
    BOOL parked = plan.parked && !self.edgeExpanded;
    self.desktopActionParked = parked;
    self.desktopActionHalfHidden = toggleHalfHidden;
    // A changing clipped viewport must not race independently animated child
    // sizes and scroll bounds. Commit resize geometry together, then keep the
    // normal animation timing for subsequent moves within a stable viewport.
    // A changing clipped viewport must not race independently animated children,
    // but zeroing the duration for the whole pass turned every bubble into an
    // instant jump on each split/fullscreen toggle. Commit the new size first and
    // let the children keep a normal, short duration.
    // A resized viewport only needs the container's own size committed without an
    // animation race. Zeroing the duration for every child made the whole column
    // snap on each split/fullscreen toggle, including the toggle's move to the
    // edge. Children keep a short but real duration.
    BOOL viewportResized = !CGSizeEqualToSize(self.rail.bounds.size, railFrame.size) ||
        !CGSizeEqualToSize(self.favoritesRail.bounds.size, favoritesFrame.size);
    CGFloat childDuration = viewportResized ? (UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.22) : layoutDuration;
    BOOL hideEdgeIcons = NO;
    self.rail.hidden = rowCount == 0;
    self.railMaterial.hidden = rowCount == 0;
    // The whole visible column - unread rows included - is half hidden in the
    // collapsed fullscreen state: the rail, every row and the control share the
    // same shift and the same 0.5 alpha, so no unread icon stays fully visible.
    CGFloat columnAlpha = halfHiddenColumn ? 0.5 : 1;
    CGFloat targetRailAlpha = rowCount ? columnAlpha : 0;
    CGFloat targetMaterialAlpha = rowCount && height > 0 ? 0.55 * columnAlpha : 0;
    BOOL railSizeChanged = !CGSizeEqualToSize(self.rail.bounds.size, railFrame.size);
    // Narrow only the visible edge material. Keep the rail's padded area so icon
    // edges, shadows and the unread badges inside the icon stay intact.
    CGRect materialFrame = edgeMode ? CGRectInset(railFrame, 5, 0) : railFrame;
    self.rail.alwaysBounceVertical = contentHeight > height;
    self.rail.showsVerticalScrollIndicator = NO;
    // Only a real change starts an animation: re-submitting the same frame/alpha
    // on every refresh restarted the curve and made the move look like a jump.
    BOOL railFrameChanged = NFBMotionRectMoved(self.rail.frame.origin.x, self.rail.frame.origin.y,
        self.rail.frame.size.width, self.rail.frame.size.height,
        railFrame.origin.x, railFrame.origin.y, railFrame.size.width, railFrame.size.height);
    if (railFrameChanged || NFBMotionNeedsAnimation(self.rail.alpha, targetRailAlpha) ||
        NFBMotionNeedsAnimation(self.railMaterial.alpha, targetMaterialAlpha)) {
        if (CGRectIsEmpty(self.rail.frame)) self.rail.frame = railFrame;
        [UIView animateWithDuration:layoutDuration delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
            animations:^{
                self.rail.frame = railFrame;
                self.rail.alpha = targetRailAlpha;
                self.rail.layer.cornerRadius = MIN(14, railWidth / 4);
                self.railMaterial.layer.cornerRadius = MIN(14, railWidth / 4);
                self.railMaterial.frame = materialFrame;
                self.railMaterial.alpha = targetMaterialAlpha;
            } completion:nil];
    } else {
        // No real change: nothing to animate, but a first layout (empty frame,
        // alpha 0) or a value set outside the animation still has to be committed.
        if (CGRectIsEmpty(self.rail.frame)) self.rail.frame = railFrame;
        if (self.rail.alpha != targetRailAlpha) self.rail.alpha = targetRailAlpha;
        if (self.railMaterial.alpha != targetMaterialAlpha) self.railMaterial.alpha = targetMaterialAlpha;
    }
    // The control is laid out after the column's own state (half-hidden flag,
    // alpha, frame) is known, so its fade and shift follow the same pass.
    [self layoutFavorites:favoritesFrame diameter:diameter active:active duration:childDuration];
    [self layoutDesktopAction:desktopActionFrame target:actionTarget split:splitNow
                  toggleFrame:toggleFrame duration:childDuration];
    self.rail.contentSize = CGSizeMake(railFrameWidth, contentHeight);
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
        // Rows are always placed at side/2 inside the column. The half-hidden
        // state moves the rail frame (and the control) once; adding a per-row
        // offset on top of that is what put rows at screenWidth + shift.
        CGFloat rowX = side / 2;
        CGPoint targetCenter = isClearAll ? CGPointMake(CGRectGetMidX(railFrame), clearCenterY) : CGPointMake(rowX, rowY);
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
        // Every row keeps its own opacity; the half-hidden state dims the whole
        // column (self.rail.alpha) instead, so no unread icon stays fully visible.
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
        // Geometry first: the badge is derived from imageView.frame, so laying it
        // out before the icon size is committed put it outside the icon.
        if (!isClearAll) [self layoutBadge:button diameter:diameter];
        if (!isClearAll) {
            unsigned long long version = button.badgeContentVersion;
            NSNumber *lastVersion = self.lastBadgeVersion[appID];
            if ((!lastVersion || lastVersion.unsignedLongLongValue != version) && button.badge.text.length) {
                self.lastBadgeVersion[appID] = @(version);
                if (!UIAccessibilityIsReduceMotionEnabled()) {
                    CABasicAnimation *pop = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
                    pop.fromValue = @1.25; pop.toValue = @1; pop.duration = 0.22;
                    pop.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                    [button.badge.layer addAnimation:pop forKey:@"NFBBadgePop"];
                }
            } else if (!button.badge.text.length) {
                [self.lastBadgeVersion removeObjectForKey:appID];
            }
        }
    }];
    // Collections are laid out; only now do the reminders run, on rows that are
    // really placed (NFBBurstPolicy.h).
    [self runBurstEffects];
    self.lastRefreshComplete = laidOut;
    if (laidOut) self.lastLayoutAt = CACurrentMediaTime();
    self.layoutRecording = NO;
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
        CGPoint targetCenter = CGPointMake(side / 2, NFBRowCenter(self.favoriteApps.count, index, step, side));
        BOOL changed = !CGRectEqualToRect(button.bounds, CGRectMake(0,0,side,side)) || (button != self.favoriteDrag && !CGPointEqualToPoint(button.center, targetCenter)) || !CGRectEqualToRect(button.imageView.frame, CGRectMake(7,7,diameter,diameter)) || button.imageView.layer.cornerRadius != diameter * 0.23 || button.alpha != ([app isEqual:active] ? 1 : self.iconOpacity);
        if (changed) [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            button.bounds = CGRectMake(0, 0, side, side);
            if (button != self.favoriteDrag) button.center = CGPointMake(side / 2, NFBRowCenter(self.favoriteApps.count, index, step, side));
            button.imageView.frame = CGRectMake(7, 7, diameter, diameter);
            button.imageView.layer.cornerRadius = diameter * 0.23;
            button.alpha = [app isEqual:active] ? 1 : self.iconOpacity;
        } completion:nil];
        // Same rule as the main column: the badge follows the icon geometry.
        [self layoutBadge:button diameter:diameter];
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
        // No clock at pickup: the finger's own Changed callbacks drive the row.
        self.favoriteDragFingerPoint = point;
        [self updateFavoriteDragClock];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.favoriteDrag) self.favoriteDragConsumed = YES;
        // The finger is the clock here; the timer never moves the row on its own.
        [self moveFavoriteDriven:YES];
        [self updateFavoriteDragClock];
    } else {
        [self finishFavoriteDrag]; [self refresh];
    }
}
// The 30 Hz drag clock. It used to run for the whole drag and repeat the exact
// move the finger callback had just done; now it exists only for edge
// auto-scrolling, and inside that zone the finger callback leaves the move to it,
// so every frame still moves the row exactly once (NFBFavoriteDragPolicy.h).
- (void)updateFavoriteDragClock {
    BOOL needed = self.favoriteDrag != nil && [self favoriteIdleZoneActive];
    if (!needed) {
        [self.favoriteDragTimer invalidate]; self.favoriteDragTimer = nil;
        return;
    }
    if (self.favoriteDragTimer) return;
    __weak typeof(self) weakSelf = self;
    self.favoriteDragTimer = [NSTimer timerWithTimeInterval:1.0/30.0 repeats:YES block:^(__unused NSTimer *timer) {
        NFBManager *manager = weakSelf;
        if (!manager) return;
        [manager moveFavoriteDriven:NO];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.favoriteDragTimer forMode:NSRunLoopCommonModes];
}
- (BOOL)favoriteIdleZoneActive {
    UIScrollView *rail = self.favoritesRail;
    if (!self.favoriteDrag || !rail) return false;
    if (rail.contentSize.width < 8 || rail.contentSize.height < 8) return false;
    CGPoint point = [self.favoriteHold locationInView:rail];
    NFBFavoriteDragInput in = {
        true, point.y - rail.contentOffset.y, rail.bounds.size.height, rail.contentSize.height,
        rail.contentOffset.y, false
    };
    return NFBFavoriteIdleClockActive(in, 44.0);
}
- (void)moveFavoriteDriven:(BOOL)fingerDriven {
    NFBBubble *button = self.favoriteDrag;
    if (!button) return;
    CGPoint point = [self.favoriteHold locationInView:self.favoritesRail];
    // The clock may only re-run a move when the edge scroll really changed
    // something or the finger moved; a resting finger outside the edge zone is
    // the finger callback's frame, not the timer's.
    if (!fingerDriven) {
        if (![self favoriteIdleZoneActive]) return;
        double gap = point.y - self.favoriteDragFingerPoint.y;
        if (gap < 0) gap = -gap;
        NFBFavoriteDragInput in = {
            true, point.y - self.favoritesRail.contentOffset.y, self.favoritesRail.bounds.size.height,
            self.favoritesRail.contentSize.height, self.favoritesRail.contentOffset.y, gap > 0.0001
        };
        if (!NFBFavoriteEdgeNeedsMove(in)) return;
    }
    self.favoriteDragFingerPoint = point;
    [self moveFavorite];
}
// Runs the move at most once per frame source: -updateFavoriteDragClock's timer
// and the finger callback both reach the move through this one method.
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

// Whether a point given in a view's own space lies on the part of it that is
// really on screen. A half-hidden column / control extends past the physical
// edge, so only this test may extend its own hit area; the part behind the edge
// and the area left of the control never take a touch. The on-screen range is
// [0, NFBVisibleMaxX] in the view's own space (a moved-right view keeps its left
// edge, which is local x 0, on screen).
- (BOOL)view:(UIView *)view containsVisiblePoint:(CGPoint)local {
    if (!view || !view.window || view.hidden || view.alpha < 0.01) return NO;
    CGRect frame = [view convertRect:view.bounds toView:view.window];
    if (CGRectGetWidth(frame) <= 0 || CGRectGetHeight(frame) <= 0) return NO;
    double visibleMaxX = NFBVisibleMaxX(CGRectGetMinX(frame), CGRectGetWidth(frame),
        CGRectGetWidth(view.window.bounds));
    // Local x grows rightwards with the frame, so the on-screen part ends at the
    // same distance from the left edge (view transform is identity here).
    return NFBHalfHiddenAcceptsTouch(local.x, local.y, CGRectGetWidth(frame), visibleMaxX);
}
// Screen-space touch for the collapse control while it is half hidden or parked.
- (BOOL)visibleHalfContainsTouch:(UITouch *)touch forView:(UIView *)view {
    return [self view:view containsVisiblePoint:[touch locationInView:view]];
}
- (UIView *)rail:(NFBRail *)rail bubbleAtPoint:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *candidate in rail.subviews.reverseObjectEnumerator) {
        if (![candidate isKindOfClass:NFBBubble.class] || candidate.hidden ||
            candidate.alpha < 0.01 || !candidate.userInteractionEnabled) continue;
        CGPoint local = [rail convertPoint:point toView:candidate];
        // Fully inside the rail the normal hit test already reaches the row;
        // only an on-screen part hanging past the scroll view's bounds is offered
        // here, and the row's own geometry still decides the rest.
        if (CGRectContainsPoint(rail.bounds, point)) continue;
        if ([self view:candidate containsVisiblePoint:local]) return candidate;
    }
    return nil;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture == self.desktopActionTap || gesture == self.desktopActionHold ||
        gesture == self.desktopActionSwipe) {
        self.desktopActionTouchTarget = self.desktopActionTarget;
        if (!self.enabled || [self isLocked]) return NO;
        NFBActionMode mode = [self desktopActionMode];
        NFBActionGesture kind = NFBActionTap;
        if (gesture == self.desktopActionSwipe) kind = NFBActionSwipeLeft;
        if (gesture == self.desktopActionHold) kind = NFBActionHold;
        // The hold only acts inside a split and on an expanded column; elsewhere
        // it is refused here so it can neither fire nor delay the tap, which is
        // all its disabled recognizer used to achieve.
        if (!NFBActionGestureAllowed(mode, kind, YES, NO)) return NO;
        // Toggle mode has no desktop target by design; requiring one here was why
        // the collapse control never responded to a tap.
        if (self.desktopActionToggle) {
            // The visible left half is inside the bubble bounds. Restrict only
            // half-hidden/parked controls to that on-screen interval.
            if (self.desktopActionHalfHidden || self.desktopActionParked)
                return [self visibleHalfContainsTouch:touch forView:self.desktopActionButton];
            return YES;
        }
        return self.desktopActionTouchTarget != nil;
    }
    // Rows need no special case here: the rail offers the on-screen half of a row
    // that hangs past it, and the row keeps its normal gesture handling.
    return YES;
}
- (void)appHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state==UIGestureRecognizerStateBegan) [self closeBubble:(NFBBubble *)gesture.view];
}
// Programmatic scrolling (revealing the active row, settling the offset) does not
// count as user activity; only a finger on the list does.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.rail || scrollView == self.favoritesRail) [self touchColumn];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.rail && scrollView != self.favoritesRail) return;
    // A layout-driven offset change is not an interaction; a moving finger is.
    if (scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) [self touchColumn];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == self.rail || scrollView == self.favoritesRail) [self touchColumn];
    if (scrollView == self.favoritesRail && !decelerate) [self saveFavoritePosition];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.rail || scrollView == self.favoritesRail) [self touchColumn];
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
    [self resetAutoCollapseTimer];
    if (self.favoriteDragConsumed) { self.favoriteDragConsumed = NO; return; }
    NFBBubble *button = (NFBBubble *)gesture.view;
    if (self.favoriteDrag || !button) return;
    [self tapped:button];
}
- (void)tapped:(NFBBubble *)button {
    if (button.opening || (self.buttons[button.appID] != button && self.favoriteButtons[button.appID] != button)) return;
    // Remember the user just used the column: the app switch starts a fresh
    // countdown instead of folding the list on the very next tick.
    [self touchColumn];
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
