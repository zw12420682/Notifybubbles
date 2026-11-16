#import "MWWindowView.h"
#import "MWThemeManager.h"
#import "MWSceneHelper.h"
#import "MWBackgrounderManager.h"
#import "MWPassthroughWindow.h"

#define SCALE_MODE_PLIST @"/var/mobile/Library/Preferences/com.milkyway.reborn.scalemode.plist"

@implementation MWWindowView

#pragma mark - Initialization (matches original AXWindowView init exactly)

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    MWThemeManager *theme = [MWThemeManager sharedInstance];
    [theme reload];

    self.frame = CGRectMake(0, 100, 100, 100);
    self.backgroundColor = nil;
    self.layer.cornerRadius = 5;
    self.layer.borderColor = [UIColor grayColor].CGColor;
    self.clipsToBounds = YES;
    self.isAspectLock = YES;
    self.isOpen = YES;

    // Title bar - uses autoresizingMask for width
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, theme.titleBarHeight)];
    titleBar.backgroundColor = theme.titleBarColor;
    titleBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
    self.titleBar = titleBar;

    // Main view (content container)
    UIView *mainView = [[UIView alloc] init];
    mainView.backgroundColor = [UIColor darkGrayColor];
    mainView.translatesAutoresizingMaskIntoConstraints = NO;
    mainView.clipsToBounds = YES;
    self.mainView = mainView;

    // Title label
    UILabel *label = [[UILabel alloc] initWithFrame:theme.titleLabelFrame];
    label.textColor = theme.titleLabelColor;
    label.font = [UIFont systemFontOfSize:theme.titleLabelFontSize weight:UIFontWeightBold];
    label.text = @"";
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight |
                             UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin |
                             UIViewAutoresizingFlexibleTopMargin;
    self.titleLabel = label;

    // Close button
    UIButton *closeBtn = [[UIButton alloc] initWithFrame:theme.closeButtonFrame];
    closeBtn.backgroundColor = theme.closeButtonColor;
    closeBtn.layer.cornerRadius = theme.closeButtonCornerRadius;
    closeBtn.autoresizingMask = (theme.closeButtonAnchor == NSLayoutAttributeTrailing)
        ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    [closeBtn addTarget:self action:@selector(closeButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton = closeBtn;

    // Min button
    UIButton *minBtn = [[UIButton alloc] initWithFrame:theme.minButtonFrame];
    minBtn.backgroundColor = theme.minButtonColor;
    minBtn.layer.cornerRadius = theme.minButtonCornerRadius;
    minBtn.autoresizingMask = (theme.minButtonAnchor == NSLayoutAttributeTrailing)
        ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    [minBtn addTarget:self action:@selector(minButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    self.minButton = minBtn;

    // Max button
    UIButton *maxBtn = [[UIButton alloc] initWithFrame:theme.maxButtonFrame];
    maxBtn.backgroundColor = theme.maxButtonColor;
    maxBtn.layer.cornerRadius = theme.maxButtonCornerRadius;
    maxBtn.autoresizingMask = (theme.maxButtonAnchor == NSLayoutAttributeTrailing)
        ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    [maxBtn addTarget:self action:@selector(maxButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    self.maxButton = maxBtn;

    // Size changer (bottom-right resize handle)
    UIView *sizeChanger = [[UIButton alloc] initWithFrame:theme.stretchButtonFrame];
    sizeChanger.backgroundColor = theme.stretchButtonColor;
    sizeChanger.layer.cornerRadius = theme.stretchButtonCornerRadius;
    sizeChanger.layer.borderWidth = 0;
    sizeChanger.layer.borderColor = theme.stretchButtonColor.CGColor;
    sizeChanger.autoresizingMask = (theme.stretchButtonAnchor == NSLayoutAttributeTrailing)
        ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    self.sizeChanger = sizeChanger;

    // Gestures
    UIPanGestureRecognizer *titlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(titleBarPanAction:)];
    [titleBar addGestureRecognizer:titlePan];

    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(titleBarTapAction:)];
    [titleBar addGestureRecognizer:titleTap];

    UIPanGestureRecognizer *sizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sizeChangePan:)];
    [sizeChanger addGestureRecognizer:sizePan];

    UITapGestureRecognizer *sizeDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sizeChangeDoubleTap:)];
    sizeDoubleTap.numberOfTapsRequired = 2;
    [sizeChanger addGestureRecognizer:sizeDoubleTap];

    UILongPressGestureRecognizer *sizeLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sizeChangeLongPressAction:)];
    [sizeChanger addGestureRecognizer:sizeLongPress];

    // Subview order (matches original exactly)
    [titleBar addSubview:sizeChanger];
    [titleBar addSubview:closeBtn];
    [titleBar addSubview:maxBtn];
    [titleBar addSubview:minBtn];
    [titleBar addSubview:label];

    [self addSubview:mainView];
    [self addSubview:titleBar];

    // Constraints for mainView (original uses: top=titleBarHeight, left=0, right=0, bottom=0)
    CGFloat titleH = theme.titleBarHeight;
    [self addConstraint:[NSLayoutConstraint constraintWithItem:mainView attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1 constant:titleH]];
    [self addConstraint:[NSLayoutConstraint constraintWithItem:mainView attribute:NSLayoutAttributeLeft
        relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
    [self addConstraint:[NSLayoutConstraint constraintWithItem:mainView attribute:NSLayoutAttributeRight
        relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeRight multiplier:1 constant:0]];
    [self addConstraint:[NSLayoutConstraint constraintWithItem:mainView attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];

    return self;
}

- (instancetype)initWithContentView:(UIView *)contentView identifier:(NSString *)identifier scene:(FBScene *)scene {
    self = [self init];
    if (!self) return nil;

    self.bundleIdentifier = identifier;
    self.contentView = contentView;
    self.scene = scene;
    __weak MWWindowView *weakWindow = self;
    self.mwGeometryTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        MWWindowView *window = weakWindow;
        if (!window) { [timer invalidate]; return; }
        if (window.isOpen && window.superview && window.mwLastOrientation != [window contentViewOrientation])
            [window setNeedsLayout];
    }];

    [self.mainView addSubview:contentView];

    CGRect cvFrame = [self contentViewFrame];
    CGFloat titleH = [MWThemeManager sharedInstance].titleBarHeight;

    if ([self contentViewOrientation] == 1) {
        self.frame = CGRectMake(0, 100, cvFrame.size.width * 0.5, cvFrame.size.height * 0.5 + titleH);
    } else {
        self.frame = CGRectMake(0, 100, cvFrame.size.height * 0.5, cvFrame.size.width * 0.5 + titleH);
    }

    return self;
}

#pragma mark - Content View Geometry

- (NSUInteger)contentViewOrientation {
    if (!self.scene) return 1;
    @try {
        if ([self.scene respondsToSelector:@selector(settings)]) {
            id settings = [self.scene settings];
            if ([settings respondsToSelector:@selector(interfaceOrientation)]) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                    [settings methodSignatureForSelector:@selector(interfaceOrientation)]];
                [inv setSelector:@selector(interfaceOrientation)];
                [inv setTarget:settings];
                [inv invoke];
                NSInteger val = 0;
                [inv getReturnValue:&val];
                return (NSUInteger)val;
            }
        }
    } @catch (NSException *e) {}
    return 1;
}

- (CGRect)contentViewFrame {
    if (!self.scene) return [UIScreen mainScreen].bounds;
    @try {
        if ([self.scene respondsToSelector:@selector(settings)]) {
            id settings = [self.scene settings];
            if ([settings respondsToSelector:@selector(frame)]) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                    [settings methodSignatureForSelector:@selector(frame)]];
                [inv setSelector:@selector(frame)];
                [inv setTarget:settings];
                [inv invoke];
                CGRect frame;
                [inv getReturnValue:&frame];
                if (frame.size.width > 0 && frame.size.height > 0) return frame;
            }
        }
    } @catch (NSException *e) {}
    return [UIScreen mainScreen].bounds;
}

- (void)updateContentViewFrame:(CGRect)frame {
    if (!self.scene) return;
    @try {
        id mutableSettings = nil;
        if ([self.scene respondsToSelector:@selector(mutableSettings)])
            mutableSettings = [self.scene mutableSettings];
        if (!mutableSettings) return;

        if ([mutableSettings respondsToSelector:@selector(setFrame:)]) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                [mutableSettings methodSignatureForSelector:@selector(setFrame:)]];
            [inv setSelector:@selector(setFrame:)];
            [inv setTarget:mutableSettings];
            [inv setArgument:&frame atIndex:2];
            [inv invoke];
        }

        if ([self.scene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)])
            [self.scene updateSettings:mutableSettings withTransitionContext:nil completion:nil];
    } @catch (NSException *e) {}
}

#pragma mark - Layout (matches original - uses scaling transform)

- (void)layoutSubviews {
    [super layoutSubviews];

    NSUInteger orientation = [self contentViewOrientation];
    if (orientation < 1 || orientation > 4) orientation = 1;
    BOOL landscape = UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)orientation);
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat shortSide = MIN(screen.size.width, screen.size.height);
    CGFloat longSide = MAX(screen.size.width, screen.size.height);
    CGFloat titleH = [MWThemeManager sharedInstance].titleBarHeight;
    if (self.mwLastOrientation && self.mwLastOrientation != orientation &&
        UIInterfaceOrientationIsLandscape((UIInterfaceOrientation)self.mwLastOrientation) != landscape) {
        CGRect f = self.frame;
        CGFloat contentH = MAX(1, f.size.height - titleH);
        f.size = CGSizeMake(contentH, f.size.width + titleH);
        CGFloat limit = MIN(1.0, MIN(screen.size.width / f.size.width,
                                   (screen.size.height - 44) / f.size.height));
        f.size.width *= limit; f.size.height *= limit;
        f.origin.x = MAX(0, MIN(f.origin.x, screen.size.width - f.size.width));
        f.origin.y = MAX(44, MIN(f.origin.y, screen.size.height - f.size.height));
        self.frame = f;
    }
    self.mwLastOrientation = orientation;
    // Remote layers are display-oriented. Rotate their portrait backing space
    // into the app's scene orientation before applying a uniform scale.
    CGSize backing = CGSizeMake(shortSide, longSide);
    CGSize oriented = landscape ? CGSizeMake(longSide, shortSide) : backing;
    CGSize available = CGSizeMake(self.bounds.size.width, MAX(1, self.bounds.size.height - titleH));
    CGFloat scale = MIN(available.width / oriented.width, available.height / oriented.height);
    CGFloat angle = 0;
    if (orientation == UIInterfaceOrientationLandscapeLeft) angle = M_PI_2;
    else if (orientation == UIInterfaceOrientationLandscapeRight) angle = -M_PI_2;
    else if (orientation == UIInterfaceOrientationPortraitUpsideDown) angle = M_PI;
    self.contentView.transform = CGAffineTransformIdentity;
    self.contentView.bounds = (CGRect){CGPointZero, backing};
    for (UIView *host in self.contentView.subviews) {
        host.frame = self.contentView.bounds;
    }
    self.contentView.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(angle), scale, scale);
    self.contentView.center = CGPointMake(available.width / 2, available.height / 2);

}

#pragma mark - Layer Updates

- (void)updateLayers {
    if (!self.isOpen) return;
    if (!self.scene) return;

    for (UIView *sub in [self.contentView subviews]) {
        [sub removeFromSuperview];
    }

    if (![self.scene respondsToSelector:@selector(layerManager)]) return;
    id layerManager = [self.scene layerManager];
    NSArray *layers = [layerManager layers];
    if (!layers) return;
    if (![self.contentView respondsToSelector:@selector(_createHostViewForLayer:)]) return;

    for (id layer in layers) {
        UIView *hostView = [(id)self.contentView _createHostViewForLayer:layer];
        if (!hostView) continue;

        NSString *className = NSStringFromClass([hostView class]);

        if ([className isEqualToString:@"_UIExternalSceneLayerHostView"]) {
            // The keyboard is an external scene layer. Keep it in a screen-sized
            // host window so it is not scaled together with the app content.
            static MWPassthroughWindow *kbWindow = nil;
            if (!kbWindow) {
                kbWindow = [[MWPassthroughWindow alloc] initWithNoRotation];
                kbWindow.backgroundColor = [UIColor clearColor];
                kbWindow.windowLevel = UIWindowLevelAlert + 1000;
                kbWindow.hidden = NO;
                [MWPassthroughWindow setKeyboardWindow:kbWindow];
            }
            CGRect screenFrame = [UIScreen mainScreen].bounds;
            kbWindow.frame = screenFrame;
            kbWindow.hidden = NO;
            kbWindow.accessibilityIdentifier = self.bundleIdentifier;
            hostView.frame = screenFrame;
            hostView.bounds = (CGRect){CGPointZero, screenFrame.size};
            hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            for (UIView *sub in kbWindow.subviews) {
                [sub removeFromSuperview];
            }
            [kbWindow addSubview:hostView];
        } else {
            hostView.frame = self.contentView.bounds;
            [self.contentView addSubview:hostView];
        }
    }
    [self layoutSubviews];
}

#pragma mark - Title Bar Drag (matches original exactly)

- (void)titleBarPanAction:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        CGPoint loc = [gesture locationInView:self.superview];
        CGPoint center = self.center;
        self.offset = CGPointMake(loc.x - center.x, loc.y - center.y);
        [self.superview bringSubviewToFront:self];
    }
    CGPoint loc = [gesture locationInView:self.superview];
    self.center = CGPointMake(loc.x - self.offset.x, loc.y - self.offset.y);
}

- (void)titleBarTapAction:(UITapGestureRecognizer *)gesture {
    [self.superview bringSubviewToFront:self];
}

#pragma mark - Size Change (matches original)

- (void)sizeChangePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.prevPos = [gesture locationInView:self];
        self.oldFrame = self.frame;
    }

    CGPoint current = [gesture locationInView:self];
    CGFloat dx = current.x - self.prevPos.x;
    CGFloat dy;

    if (self.isAspectLock) {
        CGRect cvFrame = [self contentViewFrame];
        NSUInteger orient = [self contentViewOrientation];
        CGFloat ratio = (orient == 1) ? (cvFrame.size.height / cvFrame.size.width)
                                      : (cvFrame.size.width / cvFrame.size.height);
        dy = ratio * dx;
    } else {
        dy = current.y - self.prevPos.y;
    }

    CGRect old = self.oldFrame;
    self.frame = CGRectMake(old.origin.x, old.origin.y, old.size.width + dx, old.size.height + (CGFloat)((float)dy));
    self.oldFrame = self.frame;
    self.prevPos = [gesture locationInView:self];
    [self.superview bringSubviewToFront:self];
    [self layoutSubviews];
}

- (void)sizeChangeDoubleTap:(UITapGestureRecognizer *)gesture {
    NSUInteger orient = [self contentViewOrientation];
    CGRect cvFrame = [self contentViewFrame];
    CGFloat targetW = (orient == 1) ? cvFrame.size.width : cvFrame.size.height;
    CGFloat targetH = (orient == 1) ? cvFrame.size.height : cvFrame.size.width;
    CGFloat titleH = [MWThemeManager sharedInstance].titleBarHeight;

    [UIView animateWithDuration:0.2 delay:0 options:0 animations:^{
        self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, targetW, targetH + titleH);
    } completion:^(BOOL finished) {
        [self layoutSubviews];
    }];

    if (self.isAspectLock) {
        self.sizeChanger.backgroundColor = [UIColor clearColor];
        self.sizeChanger.layer.borderWidth = 2;
        self.isAspectLock = NO;
    } else {
        self.sizeChanger.backgroundColor = [MWThemeManager sharedInstance].stretchButtonColor;
        self.sizeChanger.layer.borderWidth = 0;
        self.isAspectLock = YES;
    }
}

- (void)sizeChangeLongPressAction:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIDeviceOrientation orient = [UIDevice currentDevice].orientation;
        if (orient == UIDeviceOrientationPortrait)
            self.transform = CGAffineTransformIdentity;
        else if (orient == UIDeviceOrientationLandscapeLeft)
            self.transform = CGAffineTransformMakeRotation(270 * M_PI / 180.0);
    }
}

#pragma mark - Close Button (invalidate container before removal)

- (void)closeButtonAction:(id)sender {
    [self.mwGeometryTimer invalidate];
    self.mwGeometryTimer = nil;
    MWPassthroughWindow *keyboardWindow = [MWPassthroughWindow keyboardWindow];
    if ([keyboardWindow.accessibilityIdentifier isEqualToString:self.bundleIdentifier]) {
        [keyboardWindow.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        keyboardWindow.hidden = YES;
    }
    // Release assertions
    if (self.foregroundAssertion) {
        if ([self.foregroundAssertion respondsToSelector:@selector(invalidate)])
            [self.foregroundAssertion invalidate];
        self.foregroundAssertion = nil;
    }
    if (self.processAssertion) {
        if ([self.processAssertion respondsToSelector:@selector(invalidate)])
            [self.processAssertion invalidate];
        self.processAssertion = nil;
    }
    // Note: static assertion dict cleaned up by Tweak.x _didExitWithContext hook

    // Stop keep-alive timer
    [MWSceneHelper stopKeepAliveForBundleID:self.bundleIdentifier];

    NSString *sceneID = [self.scene identifier];
    if (sceneID) {
        [[MWBackgrounderManager sharedInstance] setForegroundSceneID:sceneID enabled:NO];
        [MWSceneHelper sleepScene:self.bundleIdentifier];
    }
    [MWPassthroughWindow removeWindowedId:self.bundleIdentifier];

    // Invalidate the container to prevent dealloc crash
    if ([self.contentView respondsToSelector:@selector(invalidate)]) {
        [(id)self.contentView invalidate];
    }

    [self.contentView removeFromSuperview];
    [self removeFromSuperview];
}

#pragma mark - Min Button (matches original animation blocks)

- (void)minButtonAction:(id)sender {
    MWThemeManager *theme = [MWThemeManager sharedInstance];

    if (self.isOpen) {
        self.prevFrame = self.frame;
        self.saveTitleLabelFrame = self.titleLabel.frame;
        self.saveMinButtonFrame = self.minButton.frame;

        [UIView animateWithDuration:0.2 delay:0 options:0 animations:^{
            self.layer.borderWidth = 1;
            CGRect f = self.frame;
            self.frame = CGRectMake(f.origin.x, f.origin.y, 100, theme.titleBarHeight);
            self.minButton.frame = CGRectMake(0, 0, 100, 24);
            self.titleLabel.frame = CGRectMake(0, 0, 100, 24);
            self.minButton.backgroundColor = theme.titleBarColor;
        } completion:^(BOOL finished) {
            self.layer.borderWidth = 0;
            [self layoutSubviews];
        }];
        self.isOpen = NO;
    } else {
        [UIView animateWithDuration:0.2 delay:0 options:0 animations:^{
            self.layer.borderWidth = 1;
            CGRect f = self.frame;
            CGRect pf = self.prevFrame;
            self.frame = CGRectMake(f.origin.x, f.origin.y, pf.size.width, pf.size.height);
            self.minButton.frame = self.saveMinButtonFrame;
            self.titleLabel.frame = self.saveTitleLabelFrame;
            self.minButton.backgroundColor = theme.minButtonColor;
        } completion:^(BOOL finished) {
            self.layer.borderWidth = 0;
            [self layoutSubviews];
        }];
        self.isOpen = YES;
    }
}

#pragma mark - Max Button (matches original - fullscreen)

- (void)maxButtonAction:(id)sender {
    [UIView animateWithDuration:0.2 delay:0 options:0 animations:^{
        self.frame = [UIScreen mainScreen].bounds;
    } completion:^(BOOL finished) {
        [self layoutSubviews];
    }];
}

@end
