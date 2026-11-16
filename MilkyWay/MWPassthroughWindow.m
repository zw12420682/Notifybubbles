#import "MWPassthroughWindow.h"
#import "MWWindowView.h"

static MWPassthroughWindow *_sharedInstance = nil;
static NSMutableArray *_windowedIDs = nil;
static MWPassthroughWindow *_keyboardWindow = nil;

@implementation MWPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    return (view == self) ? nil : view;
}

@end

@implementation MWPassthroughWindow

+ (void)initialize {
    if (self == [MWPassthroughWindow class]) {
        _windowedIDs = [NSMutableArray array];
    }
}

+ (instancetype)sharedInstance {
    return _sharedInstance;
}

+ (void)setSharedInstance:(MWPassthroughWindow *)instance {
    _sharedInstance = instance;
}

+ (MWPassthroughWindow *)keyboardWindow {
    return _keyboardWindow;
}

+ (void)setKeyboardWindow:(MWPassthroughWindow *)window {
    _keyboardWindow = window;
}

- (instancetype)init {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    if (scene) {
        self = [super initWithWindowScene:scene];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }

    if (self) {
        if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad) {
            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(deviceOrientationDidChange:)
                                                         name:UIDeviceOrientationDidChangeNotification
                                                       object:nil];
        }
    }
    return self;
}

- (instancetype)initWithNoRotation {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    if (scene) {
        self = [super initWithWindowScene:scene];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }

    if (self) {
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
            if (@available(iOS 13.0, *)) {
                UIWindowScene *ws = self.windowScene;
                if (ws) orientation = ws.interfaceOrientation;
            }

            CGFloat angle = 0;
            switch (orientation) {
                case UIInterfaceOrientationPortrait: angle = 0; break;
                case UIInterfaceOrientationLandscapeRight: angle = 270 * M_PI / 180.0; break;
                case UIInterfaceOrientationLandscapeLeft: angle = 90 * M_PI / 180.0; break;
                default: break;
            }
            self.transform = CGAffineTransformMakeRotation(angle);
            self.frame = [UIScreen mainScreen].bounds;
        }
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *view = [super hitTest:point withEvent:event];
    return (view == self) ? nil : view;
}

- (void)deviceOrientationDidChange:(NSNotification *)notification {
    UIDevice *device = notification.object;
    UIDeviceOrientation orientation = device.orientation;

    CGFloat angle = 0;
    switch (orientation) {
        case UIDeviceOrientationPortrait: angle = 0; break;
        case UIDeviceOrientationLandscapeRight: angle = 90 * M_PI / 180.0; break;
        case UIDeviceOrientationLandscapeLeft: angle = 270 * M_PI / 180.0; break;
        default: return;
    }

    [UIView animateWithDuration:0.3 delay:0 options:0 animations:^{
        self.transform = CGAffineTransformMakeRotation(angle);
        self.frame = [UIScreen mainScreen].bounds;
    } completion:nil];
}

+ (BOOL)isWindowed:(NSString *)bundleID {
    if (!bundleID) return NO;
    for (NSString *wid in _windowedIDs) {
        if ([wid isEqualToString:bundleID]) return YES;
    }
    return NO;
}

+ (void)addWindowedId:(NSString *)bundleID {
    if (bundleID && ![_windowedIDs containsObject:bundleID])
        [_windowedIDs addObject:bundleID];
}

+ (void)removeWindowedId:(NSString *)bundleID {
    if (bundleID)
        [_windowedIDs removeObject:bundleID];
}

+ (void)notifyUpdateLayers {
    MWPassthroughWindow *window = [self sharedInstance];
    if (!window) return;

    UIView *rootView = window;
    if (window.rootViewController) {
        rootView = window.rootViewController.view ?: window;
    }

    for (UIView *subview in rootView.subviews) {
        if ([subview isKindOfClass:[MWWindowView class]]) {
            [(MWWindowView *)subview updateLayers];
        }
    }
}

@end
