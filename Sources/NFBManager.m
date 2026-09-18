#import "NFBManager.h"
#import "NFBPrivate.h"
#import "NFBStore.h"
#import "NFBGeometry.h"
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
@property(nonatomic) CGFloat iconSize;
@property(nonatomic) CGFloat iconOpacity;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL showLock;
@property(nonatomic) BOOL showHome;
@property(nonatomic) BOOL showApps;
- (void)refresh;
- (void)burstBubble:(NFBBubble *)button;
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
        [self reloadPreferences];
    }
    return self;
}
- (void)reloadPreferences {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    CFPreferencesAppSynchronize(NFBDomain);
    self.iconSize = NFBSize(NFBNumber(@"IconSize", 48));
    self.iconOpacity = NFBOpacity(NFBNumber(@"IconOpacity", 1));
    self.enabled = NFBPreference(@"Enabled", YES);
    self.showLock = NFBPreference(@"ShowOnLock", YES);
    self.showHome = NFBPreference(@"ShowOnHome", YES);
    self.showApps = NFBPreference(@"ShowInApps", YES);
    if (!self.enabled) [self clear];
    else [self refresh];
}
- (void)receiveRequest:(id)request destination:(id)destination {
    if (!self.enabled) return;
    NSString *appID = NFBString(NFBGet(request, @"sectionIdentifier"));
    NSString *notificationID = NFBString(NFBGet(request, @"notificationIdentifier"));
    if (!appID.length || !notificationID.length || !NFBGet(request, @"defaultAction")) return;
    BOOL firstAppearance = ![self.store.appIDs containsObject:appID];
    [self.store putApp:appID notification:notificationID request:request destination:destination];
    id image = NFBGet(NFBGet(request, @"content"), @"icon");
    if ([image isKindOfClass:UIImage.class]) self.icons[appID] = image;
    // Each app owns its own deadline. A newer message replaces the old deadline.
    NSTimeInterval hold = firstAppearance ? 4.2 : 3.6;
    NSNumber *deadline = @(CACurrentMediaTime() + hold);
    self.expandedUntil[appID] = deadline;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.expandedUntil[appID] isEqual:deadline]) [self refresh];
    });
    if (!self.timer) {
        __weak NFBManager *weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(__unused NSTimer *timer) {
            [weakSelf refresh];
        }];
        self.timer.tolerance = 0.15;
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
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
- (void)clear {
    [self.store clear]; [self.expandedUntil removeAllObjects]; [self.icons removeAllObjects]; [self refresh];
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
    button.accessibilityHint = @"点击打开本应用通知，长按关闭此气泡";
    id image = self.icons[button.appID];
    button.imageView.image = [image isKindOfClass:UIImage.class] ? image : [UIImage systemImageNamed:@"bell.fill"];
}
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"UI must be on main thread");
    NSArray<NSString *> *apps = self.store.appIDs;
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
        [self.timer invalidate]; self.timer = nil;
        // Delay hiding until the removal animation completes; recheck new arrivals.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.store.appIDs.count || !self.enabled) self.window.hidden = YES;
        });
        return;
    }
    if (![self shouldShow]) { self.window.hidden = YES; return; }
    [self ensureWindow];
    self.window.hidden = NO;
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
    self.rail.frame = CGRectMake(bounds.size.width - side, top + (available - height) * 0.42, side, height);
    self.rail.contentSize = CGSizeMake(side, apps.count * step);
    CGFloat maxOffset = MAX(0, self.rail.contentSize.height - height);
    if (self.rail.contentOffset.y > maxOffset) self.rail.contentOffset = CGPointMake(0, maxOffset);
    [apps enumerateObjectsUsingBlock:^(NSString *appID, NSUInteger index, __unused BOOL *stop) {
        NFBBubble *button = self.buttons[appID];
        BOOL fresh = !button;
        if (fresh) {
            button = [[NFBBubble alloc] initWithFrame:CGRectZero];
            button.appID = appID;
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
            press.minimumPressDuration = 0.55;
            press.cancelsTouchesInView = YES;
            [button addGestureRecognizer:press];
            self.buttons[appID] = button;
            [self.rail addSubview:button];
        }
        [self updateBubble:button record:[self.store latestForApp:appID]];
        BOOL expanded = [self.expandedUntil[appID] doubleValue] > CACurrentMediaTime();
        CGAffineTransform target = CGAffineTransformMakeTranslation(expanded ? 0 : NFBRetraction(diameter), 0);
        CGRect targetBounds = CGRectMake(0, 0, side, side);
        CGPoint targetCenter = CGPointMake(side / 2, index * step + side / 2);
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
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : (fresh ? 1.2 : 0.6)
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
- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NFBBubble *button = (NFBBubble *)gesture.view;
    if (self.buttons[button.appID] != button) return;
    [self.burstApps addObject:button.appID];
    [self.store closeApp:button.appID];
    [self.expandedUntil removeObjectForKey:button.appID];
    [self refresh];
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
- (void)tapped:(NFBBubble *)button {
    NFBRecord *record = [self.store latestForApp:button.appID];
    if (!record) {
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"暂无可打开的新通知，长按可关闭图标");
        return;
    }
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
        return;
    }
    @try {
        [delegate destination:record.destination executeAction:action forNotificationRequest:record.request
            requestAuthentication:YES withParameters:@{} completion:^{}];
        // The system handles authentication and the app's read state.
        // Do not mutate any bubble here: cancellation and other apps stay intact.
    } @catch (__unused NSException *error) {
        NSLog(@"[NotifyBubbles] Notification action failed; bubbles retained.");
    }
}
@end
