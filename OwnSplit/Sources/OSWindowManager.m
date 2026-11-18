#import "OSWindowManager.h"
#import "OSFloatingWindow.h"
#import "OSSceneHost.h"
#import "OSAppPicker.h"
#import "OSSettings.h"
#import "OSPassthroughWindow.h"
#import "OSSplitView.h"
#import <objc/message.h>

@interface OSWindowManager ()
@property (nonatomic, strong, nullable) OSPassthroughWindow *overlayWindow;
@property (nonatomic, strong) OSPassthroughView *overlayRoot;
@property (nonatomic, strong, readwrite) NSMutableArray<OSFloatingWindow *> *mutableFloatingWindows;
@property (nonatomic, assign, readwrite) OSPresentationMode mode;
@property (nonatomic, strong, nullable) OSAppPicker *picker;
@property (nonatomic, strong, nullable) OSSplitView *splitView;
@property (nonatomic, strong) NSMutableSet<NSString *> *mutableHostedBundleIDs;
@property (nonatomic, strong) NSMutableSet<NSString *> *launchAllowlist; // 临时允许全屏一次
@property (nonatomic, assign) BOOL suppressLaunch;
@property (nonatomic, assign) BOOL homeReturnPending;
@property (nonatomic, copy, nullable) NSString *pendingHomeBundleID;
@property (nonatomic, weak, nullable) UIWindow *keyWindowBeforeHostedInput;
@property (nonatomic, assign) BOOL hostedInputActive;
- (void)openFloatingWithBundleID:(NSString *)bundleID reusingHost:(nullable OSSceneHost *)reusableHost;
- (void)makeOverlayKeyWindow;
- (void)ensureOverlayVisible;
- (void)restorePreviousKeyWindow;
- (id)sharedRemoteKeyboards;
- (void)configureRemoteKeyboardsForHostedInput:(BOOL)enabled;
- (void)configureReconnectForHost:(OSSceneHost *)host;
- (BOOL)ownsSceneHost:(OSSceneHost *)host;
@end

@implementation OSWindowManager

+ (instancetype)shared {
    static OSWindowManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OSWindowManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableFloatingWindows = [NSMutableArray array];
        _mutableHostedBundleIDs = [NSMutableSet set];
        _launchAllowlist = [NSMutableSet set];
        _mode = OSPresentationModeNone;
        _suppressLaunch = NO;
        _homeReturnPending = NO;
        _hostedInputActive = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(settingsChanged)
                                                      name:kOSSettingsChangedNotification
                                                    object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                   selector:@selector(hostedKeyboardWillHide)
                                                       name:UIKeyboardWillHideNotification
                                                     object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                   selector:@selector(hostedKeyboardWillShow)
                                                       name:UIKeyboardWillShowNotification
                                                     object:nil];
    }
    return self;
}

- (NSArray<OSFloatingWindow *> *)floatingWindows {
    return [self.mutableFloatingWindows copy];
}

- (NSSet<NSString *> *)hostedBundleIDs {
    return [self.mutableHostedBundleIDs copy];
}

#pragma mark - Install（独立顶层窗口）

- (void)installInWindow:(UIWindow *)window {
    (void)window;
    [self install];
}

- (void)install {
    if (self.overlayWindow && self.overlayWindow.hidden == NO) {
        [self bringOverlayToFront];
        return;
    }

    CGRect bounds = [UIScreen mainScreen].bounds;
    OSPassthroughWindow *win = nil;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeWindowScene];
        if (scene) {
            win = [[OSPassthroughWindow alloc] initWithWindowScene:scene];
            win.frame = scene.coordinateSpace.bounds;
        }
    }
    if (!win) {
        win = [[OSPassthroughWindow alloc] initWithFrame:bounds];
    }

    win.windowLevel = UIWindowLevelStatusBar + 120.0;
    win.backgroundColor = [UIColor clearColor];
    win.hidden = NO;

    UIViewController *rootVC = [[UIViewController alloc] init];
    OSPassthroughView *root = [[OSPassthroughView alloc] initWithFrame:win.bounds];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = [UIColor clearColor];
    rootVC.view = root;
    win.rootViewController = rootVC;

    self.overlayWindow = win;
    self.overlayRoot = root;

    NSLog(@"[OwnSplit] 顶层窗口已安装 level=%.0f", win.windowLevel);
}

- (UIWindowScene *)activeWindowScene API_AVAILABLE(ios(13.0)) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState == UISceneActivationStateForegroundActive) return ws;
        if (!fallback) fallback = ws;
    }
    return fallback;
}

- (void)bringOverlayToFront {
    if (!self.overlayWindow) {
        [self install];
        return;
    }
    self.overlayWindow.hidden = NO;
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 120.0;
    // 重新挂到当前 scene（切 App 后 scene 可能变）
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeWindowScene];
        if (scene && self.overlayWindow.windowScene != scene) {
            self.overlayWindow.windowScene = scene;
            self.overlayWindow.frame = scene.coordinateSpace.bounds;
            self.overlayRoot.frame = self.overlayWindow.bounds;
        }
    }
    // 不抢 keyWindow，只确保可见
    self.overlayWindow.hidden = NO;
}

- (UIView *)contentParent {
    [self install];
    [self bringOverlayToFront];
    return self.overlayRoot;
}

#pragma mark - Activation

- (void)handleActivationRequest {
    if (![OSSettings shared].isEnabled) return;
    [self install];

    [self presentAppPickerWithCompletion:^(NSString *bundleID) {
        if (bundleID) [self openFloatingWithBundleID:bundleID];
    }];
}

- (void)handleActivationForBundleID:(NSString *)bundleID {
    [self handleActivationForBundleID:bundleID preferredMode:OSPresentationModeNone];
}

- (void)handleActivationForBundleID:(NSString *)bundleID preferredMode:(OSPresentationMode)mode {
    if (![OSSettings shared].isEnabled) return;
    if (!bundleID.length) { [self handleActivationRequest]; return; }
    if ([[OSSettings shared] isBundleBlacklisted:bundleID]) return;
    [self install];
    if (mode == OSPresentationModeSplit) {
        NSString *primary = [self foregroundBundleID];
        if (!primary.length || [primary isEqualToString:bundleID]) primary = @"com.apple.springboard";
        [self openSplitWithPrimary:primary secondary:bundleID];
    } else {
        [self openFloatingWithBundleID:bundleID];
    }
}

- (void)presentAppPickerWithCompletion:(void (^)(NSString * _Nullable))completion {
    if (self.picker) {
        [self.picker dismissAnimated:NO];
        self.picker = nil;
    }
    UIView *parent = [self contentParent];
    self.picker = [[OSAppPicker alloc] init];
    __weak typeof(self) weakSelf = self;
    [self.picker presentInView:parent
                     favorites:[OSSettings shared].favorites
                     blacklist:[OSSettings shared].blacklist
                    completion:^(NSString *bundleID) {
        weakSelf.picker = nil;
        if (completion) completion(bundleID);
    }];
}

#pragma mark - Open

- (void)openBundleID:(NSString *)bundleID inMode:(OSPresentationMode)mode {
    (void)mode;
    [self openFloatingWithBundleID:bundleID];
}

- (void)openFloatingWithBundleID:(NSString *)bundleID {
    [self openFloatingWithBundleID:bundleID reusingHost:nil];
}

- (void)openFloatingWithBundleID:(NSString *)bundleID
                     reusingHost:(OSSceneHost *)reusableHost {
    if (!bundleID.length) return;
    if ([[OSSettings shared] isBundleBlacklisted:bundleID]) return;

    for (OSFloatingWindow *existing in self.mutableFloatingWindows) {
        if ([existing.bundleID isEqualToString:bundleID]) {
            [existing bringToFront];
            if (!existing.sceneHost.isLive) [existing.sceneHost retryAttach];
            [self bringOverlayToFront];
            return;
        }
    }

    // 关键：先登记托管，再画 UI —— 阻止随后的全屏启动
    [self.mutableHostedBundleIDs addObject:bundleID];
    self.suppressLaunch = YES;

    NSInteger max = [OSSettings shared].maxFloatingWindows;
    while ((NSInteger)self.mutableFloatingWindows.count >= max) {
        OSFloatingWindow *oldest = self.mutableFloatingWindows.firstObject;
        [self closeFloatingWindow:oldest animated:YES];
    }

    UIView *parent = [self contentParent];
    CGRect frame = [self initialFloatingFrameInBounds:parent.bounds];
    OSFloatingWindow *window = [[OSFloatingWindow alloc] initWithBundleID:bundleID frame:frame];
    window.contentOpacity = [OSSettings shared].floatingOpacity;
    window.cornerRadiusValue = [OSSettings shared].floatingCornerRadius;
    window.showsBorder = [OSSettings shared].showBorder;

    // 先占位，等 frame 落地后再创建 host，避免 0 尺寸 host view
    __weak typeof(self) weakSelf = self;
    window.onClose = ^(OSFloatingWindow *w) {
        [weakSelf closeFloatingWindow:w animated:YES];
    };
    window.onFocus = ^(OSFloatingWindow *w) {
        for (OSFloatingWindow *other in weakSelf.mutableFloatingWindows) {
            [other setActive:(other == w) animated:YES];
        }
        [weakSelf bringOverlayToFront];
    };
    window.onFrameChanged = ^(OSFloatingWindow *w, CGRect f) {
        [[OSSettings shared] setLastFloatingFrame:f];
        (void)w;
    };

    [parent addSubview:window];
    [self.mutableFloatingWindows addObject:window];
    self.mode = OSPresentationModeFloating;
    [self bringOverlayToFront];
    [self makeOverlayKeyWindow];

    // layout 后再挂 host，保证 contentContainer 有真实尺寸
    [window setNeedsLayout];
    [window layoutIfNeeded];
    OSSceneHost *host = reusableHost ?: [[OSSceneHost alloc] initWithBundleID:bundleID];
    [self configureReconnectForHost:host];
    [window attachSceneHost:host];

    if ([OSSettings shared].animateTransitions) {
        window.alpha = 0;
        window.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:0 animations:^{
            window.alpha = 1;
            window.transform = CGAffineTransformIdentity;
        } completion:nil];
    }

    [self ensureSceneThenAttach:bundleID host:host onAttached:^{
        [weakSelf bringOverlayToFront];
    }];

    NSLog(@"[OwnSplit] 打开悬浮窗 %@", bundleID);
}

- (void)closeSplitAnimated:(BOOL)animated {
    OSSplitView *view = self.splitView;
    if (!view) return;
    NSString *primary = view.primaryBundleID, *secondary = view.secondaryBundleID;
    if (primary.length) [self.mutableHostedBundleIDs removeObject:primary];
    if (secondary.length) [self.mutableHostedBundleIDs removeObject:secondary];
    OSSceneHost *pHost = [view primaryHost];
    OSSceneHost *sHost = [view secondaryHost];
    self.splitView = nil;
    self.mode = OSPresentationModeNone;
    self.suppressLaunch = NO;
    pHost.onReconnectRequested = nil;
    pHost.onOrientationChanged = nil;
    sHost.onReconnectRequested = nil;
    sHost.onOrientationChanged = nil;
    [view dismissAnimated:animated completion:nil];
    [self restorePreviousKeyWindow];
}

- (BOOL)ownsSceneHost:(OSSceneHost *)host {
    if (!host) return NO;
    if (self.splitView.primaryHost == host || self.splitView.secondaryHost == host) return YES;
    for (OSFloatingWindow *w in self.mutableFloatingWindows) if (w.sceneHost == host) return YES;
    return NO;
}

- (void)configureReconnectForHost:(OSSceneHost *)host {
    if (!host) return;
    __weak typeof(self) weakSelf = self;
    __weak OSSceneHost *weakHost = host;
    host.onReconnectRequested = ^(OSSceneHost *requested) {
        __strong typeof(weakSelf) self2 = weakSelf;
        __strong OSSceneHost *host2 = weakHost;
        if (!self2 || !host2 || requested != host2 || ![self2 ownsSceneHost:host2]) return;
        [self2 openApplicationSuspended:host2.bundleID];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![self2 ownsSceneHost:host2] || host2.isLive) return;
            [host2 retryAttach];
        });
    };
    host.onOrientationChanged = ^(OSSceneHost *changed) {
        __strong typeof(weakSelf) self2 = weakSelf;
        if (!self2 || ![self2 ownsSceneHost:changed]) return;
        [self2.splitView setNeedsLayout];
        [self2.splitView layoutIfNeeded];
        for (OSFloatingWindow *w in self2.mutableFloatingWindows) if (w.sceneHost == changed) [w setNeedsLayout];
    };
}

- (void)openSplitWithPrimary:(NSString *)primary secondary:(NSString *)secondary {
    if (!secondary.length || [[OSSettings shared] isBundleBlacklisted:secondary]) return;
    if ([primary isEqualToString:secondary]) primary = @"com.apple.springboard";
    if (self.splitView && [self.splitView.primaryBundleID isEqualToString:primary] &&
        [self.splitView.secondaryBundleID isEqualToString:secondary]) { [self bringOverlayToFront]; return; }
    if (self.splitView) [self closeSplitAnimated:NO];
    for (OSFloatingWindow *w in [self.mutableFloatingWindows copy]) [self closeFloatingWindow:w animated:NO];
    UIView *parent = [self contentParent];
    [self.mutableHostedBundleIDs addObject:secondary];
    BOOL primaryIsHome = !primary.length || [primary isEqualToString:@"com.apple.springboard"];
    if (!primaryIsHome) [self.mutableHostedBundleIDs addObject:primary];
    self.suppressLaunch = YES;
    OSSplitView *split = [[OSSplitView alloc] initWithPrimaryBundle:(primary ?: @"com.apple.springboard")
                                                   secondaryBundle:secondary ratio:[OSSettings shared].lastSplitRatio];
    split.frame = parent.bounds;
    split.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak typeof(self) weakSelf = self;
    split.onRatioChanged = ^(CGFloat ratio) {
        [[OSSettings shared] setLastSplitRatio:ratio];
    };
    split.onClose = ^{ [weakSelf closeSplitAnimated:YES]; };
    split.onPromoteSecondaryToFloating = ^(NSString *bundleID) {
        OSSplitView *active = weakSelf.splitView;
        if (!active) return;
        OSSceneHost *promoted = [active detachSecondaryHost];
        NSString *oldPrimary = active.primaryBundleID, *oldSecondary = active.secondaryBundleID;
        [weakSelf.mutableHostedBundleIDs removeObject:oldPrimary];
        [weakSelf.mutableHostedBundleIDs removeObject:oldSecondary];
        weakSelf.splitView = nil; weakSelf.mode = OSPresentationModeNone; weakSelf.suppressLaunch = NO;
        [active dismissAnimated:YES completion:^{ [weakSelf openFloatingWithBundleID:bundleID reusingHost:promoted]; }];
    };
    [parent addSubview:split];
    self.splitView = split;
    self.mode = OSPresentationModeSplit;
    [[OSSettings shared] setLastPrimaryBundleID:primary ?: @"com.apple.springboard"];
    [[OSSettings shared] setLastSecondaryBundleID:secondary];
    [self bringOverlayToFront];
    OSSceneHost *secondaryHost = [[OSSceneHost alloc] initWithBundleID:secondary];
    [self configureReconnectForHost:secondaryHost];
    [split attachSecondaryHost:secondaryHost];
    if (!primaryIsHome) {
        OSSceneHost *primaryHost = [[OSSceneHost alloc] initWithBundleID:primary];
        [self configureReconnectForHost:primaryHost];
        [split attachPrimaryHost:primaryHost];
        [self ensureSceneThenAttach:primary host:primaryHost onAttached:^{ [weakSelf bringOverlayToFront]; }];
    } else {
        UILabel *homeHint = [[UILabel alloc] initWithFrame:split.topPane.bounds];
        homeHint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        homeHint.text = @"主屏幕"; homeHint.textAlignment = NSTextAlignmentCenter;
        homeHint.textColor = [UIColor colorWithWhite:1 alpha:.65]; homeHint.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
        [split.topPane addSubview:homeHint];
    }
    [self ensureSceneThenAttach:secondary host:secondaryHost onAttached:^{ [weakSelf bringOverlayToFront]; }];
    NSLog(@"[OwnSplit] split primary=%@ secondary=%@", primary, secondary);
}


- (void)closeFloatingWindow:(OSFloatingWindow *)window animated:(BOOL)animated {
    if (!window) return;
    if (window.bundleID) {
        [self.mutableHostedBundleIDs removeObject:window.bundleID];
    }
    [self.mutableFloatingWindows removeObject:window];
    [window closeAnimated:animated completion:nil];
    if (self.mutableFloatingWindows.count == 0) {
        self.mode = OSPresentationModeNone;
        self.suppressLaunch = NO;
        [self restorePreviousKeyWindow];
    }
}

- (void)dismissAllAnimated:(BOOL)animated {
    NSArray *copy = [self.mutableFloatingWindows copy];
    for (OSFloatingWindow *w in copy) { [self closeFloatingWindow:w animated:animated]; }
    if (self.splitView) [self closeSplitAnimated:animated];
    self.mode = OSPresentationModeNone;
    self.suppressLaunch = NO;
    [self.mutableHostedBundleIDs removeAllObjects];
    [self restorePreviousKeyWindow];
}

- (id)sharedRemoteKeyboards {
    Class remoteClass = NSClassFromString(@"_UIRemoteKeyboards");
    if (!remoteClass) return nil;
    SEL shared = NSSelectorFromString(@"sharedRemoteKeyboards");
    if (![remoteClass respondsToSelector:shared]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(remoteClass, shared);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

- (void)configureRemoteKeyboardsForHostedInput:(BOOL)enabled {
    id keyboards = [self sharedRemoteKeyboards];
    if (!keyboards) return;

    @try {
        SEL setSuppressing = NSSelectorFromString(@"setSuppressingKeyboard:");
        if ([keyboards respondsToSelector:setSuppressing]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(keyboards, setSuppressing, !enabled);
        }
    } @catch (__unused NSException *exception) {}

    @try {
        SEL setWindowEnabled = NSSelectorFromString(@"setWindowEnabled:");
        if ([keyboards respondsToSelector:setWindowEnabled]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(keyboards, setWindowEnabled, enabled);
        }
    } @catch (__unused NSException *exception) {}

    if (enabled) {
        @try {
            SEL setCurrentKeyboard = NSSelectorFromString(@"setCurrentKeyboard:");
            if ([keyboards respondsToSelector:setCurrentKeyboard]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(keyboards, setCurrentKeyboard, YES);
            }
        } @catch (__unused NSException *exception) {}

        @try {
            SEL prepareHosted = NSSelectorFromString(@"prepareForHostedWindow");
            if ([keyboards respondsToSelector:prepareHosted]) {
                ((id (*)(id, SEL))objc_msgSend)(keyboards, prepareHosted);
            }
        } @catch (__unused NSException *exception) {}

        @try {
            SEL clean = NSSelectorFromString(@"cleanSuppression");
            if ([keyboards respondsToSelector:clean]) {
                ((void (*)(id, SEL))objc_msgSend)(keyboards, clean);
            }
        } @catch (__unused NSException *exception) {}
    } else {
        @try {
            SEL finishHosted = NSSelectorFromString(@"finishWithHostedWindow");
            if ([keyboards respondsToSelector:finishHosted]) {
                ((void (*)(id, SEL))objc_msgSend)(keyboards, finishHosted);
            }
        } @catch (__unused NSException *exception) {}
    }
}

- (void)prepareForHostedInput {
    if (!self.overlayWindow || self.overlayWindow.hidden) return;
    // Keep OwnSplit chrome above SpringBoard, but do not permanently steal the
    // keyboard arbiter from third-party IMEs such as WeChat Keyboard.
    [self ensureOverlayVisible];
    [self configureRemoteKeyboardsForHostedInput:YES];
}

- (void)prepareForHostedInputForView:(UIView *)view {
    if (!view) { [self prepareForHostedInput]; return; }
    OSSceneHost *target = nil;
    for (OSFloatingWindow *window in self.mutableFloatingWindows) {
        if (view == window.sceneHost.view || [view isDescendantOfView:window.sceneHost.view]) { target=window.sceneHost; break; }
    }
    if (!target && self.splitView.primaryHost && (view==self.splitView.primaryHost.view || [view isDescendantOfView:self.splitView.primaryHost.view])) target=self.splitView.primaryHost;
    if (!target && self.splitView.secondaryHost && (view==self.splitView.secondaryHost.view || [view isDescendantOfView:self.splitView.secondaryHost.view])) target=self.splitView.secondaryHost;
    [self ensureOverlayVisible];
    [self configureRemoteKeyboardsForHostedInput:YES];
    [target prepareForInput];
}

- (void)ensureOverlayVisible {
    if (!self.overlayWindow) return;
    self.overlayWindow.hidden = NO;
    [self bringOverlayToFront];
}

- (void)makeOverlayKeyWindow {
    if (!self.overlayWindow || self.overlayWindow.hidden) return;
    if (!self.hostedInputActive) {
        UIWindow *current = [UIApplication sharedApplication].keyWindow;
        if (current != self.overlayWindow) self.keyWindowBeforeHostedInput = current;
        self.hostedInputActive = YES;
    }
    // Prefer visibility over becoming the exclusive key window. Third-party
    // keyboards often need SpringBoard/remote keyboard ownership intact.
    [self ensureOverlayVisible];
}

- (void)restorePreviousKeyWindow {
    [self configureRemoteKeyboardsForHostedInput:NO];
    if (!self.hostedInputActive) return;
    self.hostedInputActive = NO;
    UIWindow *target = self.keyWindowBeforeHostedInput;
    self.keyWindowBeforeHostedInput = nil;
    if (target && target != self.overlayWindow && !target.hidden) {
        [target makeKeyWindow];
    } else if (self.overlayWindow.isKeyWindow) {
        [self.overlayWindow resignKeyWindow];
    }
}

- (void)hostedKeyboardWillShow {
    if (self.mode != OSPresentationModeNone) {
        [self prepareForHostedInput];
    }
}

- (void)hostedKeyboardWillHide {
    // Keep remote keyboard support armed while a hosted app is open. UIKit
    // sends hide notifications while changing text fields.
    if (self.mutableFloatingWindows.count > 0 || self.splitView != nil) {
        [self configureRemoteKeyboardsForHostedInput:YES];
        return;
    }
    [self restorePreviousKeyWindow];
}

- (void)handleOrientationChange {
    if (self.overlayWindow) {
        CGRect bounds = [UIScreen mainScreen].bounds;
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = self.overlayWindow.windowScene ?: [self activeWindowScene];
            if (scene) bounds = scene.coordinateSpace.bounds;
        }
        self.overlayWindow.frame = bounds;
        self.overlayRoot.frame = self.overlayWindow.bounds;
    }
    if (self.splitView) { self.splitView.frame = self.overlayRoot.bounds; [self.splitView setNeedsLayout]; [self.splitView layoutIfNeeded]; }
    for (OSFloatingWindow *w in self.mutableFloatingWindows) {
        CGRect f = w.frame;
        CGRect bounds = self.overlayRoot.bounds;
        if (CGRectGetMaxX(f) < 40) f.origin.x = 0;
        if (CGRectGetMaxY(f) < 40) f.origin.y = 0;
        if (f.origin.x > bounds.size.width - 40) f.origin.x = bounds.size.width - f.size.width;
        if (f.origin.y > bounds.size.height - 40) f.origin.y = bounds.size.height - 40;
        w.frame = f;
        [w commitSceneLayout];
    }
    [self bringOverlayToFront];
}

#pragma mark - Launch suppress

- (BOOL)shouldSuppressFullscreenForBundleID:(NSString *)bundleID {
    if (!bundleID.length) return NO;
    // 临时放行：为了创建 scene 允许启动一次
    if ([self.launchAllowlist containsObject:bundleID]) {
        return NO;
    }
    // 只有我们真正在展示悬浮/分屏时才拦截；避免误伤普通启动
    if (self.mode == OSPresentationModeNone) return NO;
    if ([self.mutableHostedBundleIDs containsObject:bundleID]) return YES;
    return NO;
}

- (void)allowNextLaunchForBundleID:(NSString *)bundleID {
    if (bundleID.length) [self.launchAllowlist addObject:bundleID];
}

- (void)handlePotentialFullscreenActivationForBundleID:(NSString *)bundleID {
    if (![self shouldSuppressFullscreenForBundleID:bundleID]) {
        [self bringOverlayToFront];
        return;
    }
    [self scheduleHomeReturnForBundleID:bundleID delay:0.15];
}

- (void)scheduleHomeReturnForBundleID:(NSString *)bundleID delay:(NSTimeInterval)delay {
    if (!bundleID.length) return;

    self.pendingHomeBundleID = [bundleID copy];
    if (self.homeReturnPending) return;
    self.homeReturnPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self2 = weakSelf;
        if (!self2) return;
        NSString *target = self2.pendingHomeBundleID;
        self2.pendingHomeBundleID = nil;
        self2.homeReturnPending = NO;
        if (self2.mode == OSPresentationModeNone ||
            ![self2 shouldSuppressFullscreenForBundleID:target]) {
            [self2 bringOverlayToFront];
            return;
        }
        [self2 goHome];
    });
}

/// Launch suspended and poll briefly for the scene. Foreground launch is only
/// a compatibility fallback when the suspended SpringBoard API is unavailable.
- (void)ensureSceneThenAttach:(NSString *)bundleID host:(OSSceneHost *)host onAttached:(void (^)(void))onAttached {
    if (!bundleID.length || !host || [bundleID isEqualToString:@"com.apple.springboard"]) return;
    if (host.isLive) { if (onAttached) onAttached(); return; }
    [self configureReconnectForHost:host];
    [self openApplicationSuspended:bundleID];
    __weak typeof(self) weakSelf = self;
    __weak OSSceneHost *weakHost = host;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self2 = weakSelf;
        __strong OSSceneHost *host2 = weakHost;
        if (!self2 || !host2 || ![self2 ownsSceneHost:host2] || host2.isLive) return;
        [host2 retryAttach];
        if (host2.isLive) { [self2 bringOverlayToFront]; if (onAttached) onAttached(); }
    });
}

- (BOOL)openApplicationSuspended:(NSString *)bundleID {
    if (!bundleID.length) return NO;
    UIApplication *application = [UIApplication sharedApplication];
    SEL selector = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if (![application respondsToSelector:selector]) return NO;

    @try {
        NSMethodSignature *signature = [application methodSignatureForSelector:selector];
        if (!signature) return NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = application;
        invocation.selector = selector;
        NSString *identifier = [bundleID copy];
        BOOL suspended = YES;
        [invocation setArgument:&identifier atIndex:2];
        [invocation setArgument:&suspended atIndex:3];
        [invocation invoke];

        if (signature.methodReturnLength == sizeof(BOOL)) {
            BOOL launched = NO;
            [invocation getReturnValue:&launched];
            return launched;
        }
        return YES;
    } @catch (NSException *e) {
        NSLog(@"[OwnSplit] suspended launch failed %@: %@", bundleID, e);
        return NO;
    }
}

- (void)openApplicationForeground:(NSString *)bundleID {
    if (!bundleID.length) return;

    // 优先 LSApplicationWorkspace
    Class LSApplicationWorkspace = NSClassFromString(@"LSApplicationWorkspace");
    if (LSApplicationWorkspace) {
        id workspace = ((id (*)(id, SEL))objc_msgSend)(LSApplicationWorkspace, @selector(defaultWorkspace));
        SEL sel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if ([workspace respondsToSelector:sel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(workspace, sel, bundleID);
            NSLog(@"[OwnSplit] openApplicationWithBundleID: %@", bundleID);
            return;
        }
    }

    // 兜底：SBUIController activateApplication
    Class SBUIController = NSClassFromString(@"SBUIController");
    Class SBAppController = NSClassFromString(@"SBApplicationController");
    if (SBUIController && SBAppController) {
        id ctrl = ((id (*)(id, SEL))objc_msgSend)(SBAppController, @selector(sharedInstance));
        id app = nil;
        SEL appSel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
        if ([ctrl respondsToSelector:appSel]) {
            app = ((id (*)(id, SEL, id))objc_msgSend)(ctrl, appSel, bundleID);
        }
        id ui = ((id (*)(id, SEL))objc_msgSend)(SBUIController, @selector(sharedInstance));
        SEL act = NSSelectorFromString(@"activateApplication:");
        if (app && [ui respondsToSelector:act]) {
            ((void (*)(id, SEL, id))objc_msgSend)(ui, act, app);
            NSLog(@"[OwnSplit] activateApplication: %@", bundleID);
        }
    }
}

- (void)goHome {
    Class SBUIController = NSClassFromString(@"SBUIController");
    if (!SBUIController) return;
    id ui = ((id (*)(id, SEL))objc_msgSend)(SBUIController, @selector(sharedInstance));
    for (NSString *name in @[@"handleHomeButtonSinglePressUp", @"clickedMenuButton"]) {
        SEL sel = NSSelectorFromString(name);
        if ([ui respondsToSelector:sel]) {
            ((void (*)(id, SEL))objc_msgSend)(ui, sel);
            NSLog(@"[OwnSplit] 回桌面 via %@", name);
            break;
        }
    }
    [self bringOverlayToFront];
}

#pragma mark - Helpers

- (CGRect)initialFloatingFrameInBounds:(CGRect)bounds {
    CGRect last = [OSSettings shared].lastFloatingFrame;
    if (!CGRectIsNull(last) && !CGRectIsEmpty(last)) {
        last.size.width = MIN(last.size.width, bounds.size.width);
        last.size.height = MIN(last.size.height, bounds.size.height);
        last.origin.x = MIN(MAX(0, last.origin.x), MAX(0, bounds.size.width - last.size.width));
        last.origin.y = MIN(MAX(0, last.origin.y), MAX(0, bounds.size.height - last.size.height));
        return last;
    }
    CGSize size = [OSSettings shared].defaultFloatingSize;
    size.width = MIN(size.width, bounds.size.width - 24);
    size.height = MIN(size.height, bounds.size.height - 48);
    CGFloat x = bounds.size.width - size.width - 12;
    CGFloat y = MAX(48, (bounds.size.height - size.height) / 2.0);
    CGFloat stagger = self.mutableFloatingWindows.count * 24.0;
    return CGRectMake(x - stagger, y + stagger, size.width, size.height);
}

- (NSString *)foregroundBundleID {
    Class SBAppController = NSClassFromString(@"SBApplicationController");
    if (SBAppController) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id controller = [SBAppController performSelector:@selector(sharedInstance)];
#pragma clang diagnostic pop
        NSArray *sels = @[@"frontmostApplication", @"_frontMostApplication", @"focusedApplication"];
        for (NSString *name in sels) {
            SEL sel = NSSelectorFromString(name);
            if ([controller respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id app = [controller performSelector:sel];
#pragma clang diagnostic pop
                NSString *bid = [app valueForKey:@"bundleIdentifier"];
                if (bid.length) return bid;
            }
        }
    }
    return nil;
}

- (void)settingsChanged {
    if (![OSSettings shared].isEnabled) {
        [self dismissAllAnimated:YES];
    }
    for (OSFloatingWindow *w in self.mutableFloatingWindows) {
        w.contentOpacity = [OSSettings shared].floatingOpacity;
        w.cornerRadiusValue = [OSSettings shared].floatingCornerRadius;
        w.showsBorder = [OSSettings shared].showBorder;
    }
}

@end
