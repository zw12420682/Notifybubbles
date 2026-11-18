#import "OSGestureController.h"
#import "OSWindowManager.h"
#import "OSSettings.h"

@interface OSGestureController () <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, strong) NSMutableArray<UIGestureRecognizer *> *recognizers;
@property (nonatomic, strong, nullable) UIScreenEdgePanGestureRecognizer *leftEdge;
@property (nonatomic, strong, nullable) UIScreenEdgePanGestureRecognizer *rightEdge;
@property (nonatomic, strong, nullable) UISwipeGestureRecognizer *threeFingerUp;
@property (nonatomic, strong, nullable) UITapGestureRecognizer *statusBarDoubleTap;
@property (nonatomic, strong, nullable) UILongPressGestureRecognizer *homeIndicatorLongPress;
@end

@implementation OSGestureController

+ (instancetype)shared {
    static OSGestureController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OSGestureController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recognizers = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadFromSettings)
                                                     name:kOSSettingsChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)installOnView:(UIView *)view {
    self.targetView = view;
    [self reloadFromSettings];
}

- (void)uninstall {
    for (UIGestureRecognizer *gr in self.recognizers) {
        [gr.view removeGestureRecognizer:gr];
    }
    [self.recognizers removeAllObjects];
    self.leftEdge = nil;
    self.rightEdge = nil;
    self.threeFingerUp = nil;
    self.statusBarDoubleTap = nil;
    self.homeIndicatorLongPress = nil;
}

- (void)reloadFromSettings {
    [self uninstall];
    UIView *view = self.targetView;
    if (!view || ![OSSettings shared].isEnabled) return;

    OSSettings *s = [OSSettings shared];

    if ([s isGestureEnabled:OSActivationGestureEdgeSwipe]) {
        self.leftEdge = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdge:)];
        self.leftEdge.edges = UIRectEdgeLeft;
        self.leftEdge.delegate = self;
        [view addGestureRecognizer:self.leftEdge];
        [self.recognizers addObject:self.leftEdge];

        self.rightEdge = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdge:)];
        self.rightEdge.edges = UIRectEdgeRight;
        self.rightEdge.delegate = self;
        [view addGestureRecognizer:self.rightEdge];
        [self.recognizers addObject:self.rightEdge];
    }

    if ([s isGestureEnabled:OSActivationGestureThreeFingerSwipeUp]) {
        self.threeFingerUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFinger:)];
        self.threeFingerUp.direction = UISwipeGestureRecognizerDirectionUp;
        self.threeFingerUp.numberOfTouchesRequired = 3;
        self.threeFingerUp.delegate = self;
        [view addGestureRecognizer:self.threeFingerUp];
        [self.recognizers addObject:self.threeFingerUp];
    }

    if ([s isGestureEnabled:OSActivationGestureStatusBarDoubleTap]) {
        self.statusBarDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStatusBarDoubleTap:)];
        self.statusBarDoubleTap.numberOfTapsRequired = 2;
        self.statusBarDoubleTap.delegate = self;
        [view addGestureRecognizer:self.statusBarDoubleTap];
        [self.recognizers addObject:self.statusBarDoubleTap];
    }

    if ([s isGestureEnabled:OSActivationGestureHomeIndicatorLongPress]) {
        self.homeIndicatorLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHomeLongPress:)];
        self.homeIndicatorLongPress.minimumPressDuration = 0.45;
        self.homeIndicatorLongPress.delegate = self;
        [view addGestureRecognizer:self.homeIndicatorLongPress];
        [self.recognizers addObject:self.homeIndicatorLongPress];
    }
}

#pragma mark - Handlers

- (void)handleEdge:(UIScreenEdgePanGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded && gr.state != UIGestureRecognizerStateRecognized) {
        // Trigger once past a sensitivity-scaled threshold
        if (gr.state == UIGestureRecognizerStateChanged) {
            CGPoint t = [gr translationInView:gr.view];
            CGFloat threshold = 40.0 + (1.0 - [OSSettings shared].edgeSwipeSensitivity) * 80.0;
            CGFloat distance = (gr.edges == UIRectEdgeLeft) ? t.x : -t.x;
            if (distance > threshold) {
                // Prevent re-fire: disable temporarily
                gr.enabled = NO;
                gr.enabled = YES;
                [self activate];
            }
        }
        return;
    }
    [self activate];
}

- (void)handleThreeFinger:(UISwipeGestureRecognizer *)gr {
    (void)gr;
    [self activate];
}

- (void)handleStatusBarDoubleTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateRecognized) return;
    CGPoint p = [gr locationInView:gr.view];
    // Only accept taps near the top ~status bar region
    CGFloat statusH = 54.0;
    if (@available(iOS 11.0, *)) {
        statusH = MAX(statusH, gr.view.safeAreaInsets.top + 10);
    }
    if (p.y <= statusH) {
        [self activate];
    }
}

- (void)handleHomeLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [gr locationInView:gr.view];
    CGFloat homeZone = 28.0;
    if (@available(iOS 11.0, *)) {
        homeZone = MAX(homeZone, gr.view.safeAreaInsets.bottom + 8);
    }
    if (p.y >= gr.view.bounds.size.height - homeZone) {
        [self activate];
    }
}

- (void)activate {
    if (![OSSettings shared].isEnabled) return;
    if ([OSSettings shared].hapticFeedback) {
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [g impactOccurred];
    }
    [[OSWindowManager shared] handleActivationRequest];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gestureRecognizer; (void)other;
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // Don't steal touches from OwnSplit chrome itself
    UIView *v = touch.view;
    while (v) {
        if ([NSStringFromClass(v.class) hasPrefix:@"OS"]) return NO;
        v = v.superview;
    }
    return YES;
}

@end
