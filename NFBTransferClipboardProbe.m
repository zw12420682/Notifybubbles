#import <UIKit/UIKit.h>

@interface NFBClipboardProbeWindow : UIWindow
@end
@implementation NFBClipboardProbeWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return v == self || v == self.rootViewController.view ? nil : v;
}
@end

@interface NFBClipboardProbeController : UIViewController
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *history;
@property(nonatomic,strong) UIStackView *records;
@property(nonatomic,strong) UIStackView *panel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) NSInteger seen;
@property(nonatomic) NSTimeInterval deadline;
@end

@implementation NFBClipboardProbeController
- (UIButton *)nfbButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.history = [NSMutableArray new];
    UIButton *toggle = [self nfbButton:@"剪贴板测试" action:@selector(nfbToggle)];
    toggle.backgroundColor = UIColor.systemIndigoColor;
    [toggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    toggle.layer.cornerRadius = 10;
    self.status = [UILabel new];
    self.status.text = @"只复制测试内容，不保存到文件";
    self.status.font = [UIFont systemFontOfSize:11];
    self.status.numberOfLines = 2;
    self.status.textAlignment = NSTextAlignmentCenter;
    self.records = [UIStackView new];
    self.records.axis = UILayoutConstraintAxisVertical;
    self.panel = [[UIStackView alloc] initWithArrangedSubviews:@[[self nfbButton:@"开始 60 秒测试" action:@selector(nfbStart)], self.status, self.records]];
    self.panel.axis = UILayoutConstraintAxisVertical;
    self.panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.panel.layer.cornerRadius = 12;
    self.panel.layoutMargins = UIEdgeInsetsMake(4, 8, 4, 8);
    self.panel.layoutMarginsRelativeArrangement = YES;
    self.panel.hidden = YES;
    [self.view addSubview:toggle];
    [self.view addSubview:self.panel];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [toggle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [toggle.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        [toggle.widthAnchor constraintEqualToConstant:108], [toggle.heightAnchor constraintEqualToConstant:40],
        [self.panel.leadingAnchor constraintEqualToAnchor:toggle.leadingAnchor],
        [self.panel.bottomAnchor constraintEqualToAnchor:toggle.topAnchor constant:-6],
        [self.panel.widthAnchor constraintEqualToConstant:200],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nfbClearOnLock:) name:UIApplicationProtectedDataWillBecomeUnavailable object:nil];
}
- (void)nfbClearOnLock:(NSNotification *)note {
    (void)note;
    [self.timer invalidate]; self.timer = nil;
    [self.history removeAllObjects]; [self nfbRender];
    self.panel.hidden = YES;
    self.status.text = @"测试已结束";
}
- (void)nfbToggle { self.panel.hidden = !self.panel.hidden; }
- (void)nfbStart {
    [self.timer invalidate];
    [self.history removeAllObjects]; [self nfbRender];
    self.seen = UIPasteboard.generalPasteboard.changeCount;
    self.deadline = NSProcessInfo.processInfo.systemUptime + 60;
    self.status.text = @"测试中：到其他 App 复制";
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *timer) {
        NFBClipboardProbeController *vc = weakSelf;
        if (vc) [vc nfbCheck]; else [timer invalidate];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)nfbCheck {
    if (!UIApplication.sharedApplication.protectedDataAvailable) {
        [self nfbClearOnLock:nil]; return;
    }
    if (NSProcessInfo.processInfo.systemUptime >= self.deadline) {
        [self.timer invalidate]; self.timer = nil;
        self.status.text = @"已停止采集，仍可点下方复制";
        return;
    }
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSInteger change = pb.changeCount;
    if (change == self.seen) return;
    self.seen = change;
    NSDictionary *entry = nil;
    if (pb.hasURLs) {
        NSURL *url = pb.URL;
        if (url.absoluteString.length && url.absoluteString.length < 8192 &&
            [@[@"http", @"https"] containsObject:url.scheme.lowercaseString ?: @""])
            entry = @{@"kind":@"链接", @"value":url};
    }
    if (!entry && pb.hasStrings) {
        NSString *text = pb.string;
        // Only specially marked test strings, never other copied text, are retained.
        if (text.length < 4096 && [text hasPrefix:@"Minis测试"])
            entry = @{@"kind":@"文字", @"value":text};
    }
    if (!entry && pb.hasImages) {
        UIImage *image = pb.image;
        if (image && image.size.width * image.scale <= 2048 && image.size.height * image.scale <= 2048)
            entry = @{@"kind":@"图片", @"value":image};
    }
    if (pb.changeCount != change) return;
    if (!entry) { self.status.text = @"检测到变化，但没有可记录的测试项"; return; }
    [self.history insertObject:entry atIndex:0];
    if (self.history.count > 3) [self.history removeLastObject];
    self.status.text = [NSString stringWithFormat:@"已记录：%@",entry[@"kind"]];
    [self nfbRender];
}
- (void)nfbRender {
    for (UIView *v in [self.records.arrangedSubviews copy]) {
        [self.records removeArrangedSubview:v]; [v removeFromSuperview];
    }
    [self.history enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger i, BOOL *stop) {
        (void)stop;
        UIButton *b = [self nfbButton:[NSString stringWithFormat:@"%lu. 复制%@",(unsigned long)(i+1),entry[@"kind"]] action:@selector(nfbCopy:)];
        b.tag = (NSInteger)i;
        [self.records addArrangedSubview:b];
    }];
}
- (void)nfbCopy:(UIButton *)button {
    if (button.tag < 0 || (NSUInteger)button.tag >= self.history.count) return;
    NSDictionary *entry = self.history[(NSUInteger)button.tag];
    id value = entry[@"value"];
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    NSString *uti = [value isKindOfClass:NSString.class] ? @"public.utf8-plain-text" :
        [value isKindOfClass:NSURL.class] ? @"public.url" : @"public.png";
    NSData *png = [value isKindOfClass:UIImage.class] ? UIImagePNGRepresentation(value) : nil;
    if ([uti isEqualToString:@"public.png"] && !png) { self.status.text = @"图片编码失败"; return; }
    [pb setItems:@[@{uti:png ?: value}] options:@{UIPasteboardOptionLocalOnly:@YES}];
    self.seen = pb.changeCount;
    self.status.text = @"已重新复制，到目标 App 粘贴";
}
@end

static NFBClipboardProbeWindow *NFBClipboardProbeOverlay;
static void NFBClipboardProbeShow(void) {
    if (NFBClipboardProbeOverlay) return;
    UIWindowScene *scene = nil, *fallback = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class] || ((UIWindowScene *)s).screen != UIScreen.mainScreen) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)s; break; }
        if (s.activationState == UISceneActivationStateForegroundInactive) fallback = (UIWindowScene *)s;
    }
    scene = scene ?: fallback;
    if (!scene) return;
    NFBClipboardProbeOverlay = [[NFBClipboardProbeWindow alloc] initWithWindowScene:scene];
    NFBClipboardProbeOverlay.windowLevel = UIWindowLevelAlert + 1;
    NFBClipboardProbeOverlay.backgroundColor = UIColor.clearColor;
    NFBClipboardProbeOverlay.rootViewController = [NFBClipboardProbeController new];
    NFBClipboardProbeOverlay.hidden = NO;
}

__attribute__((constructor)) static void NFBClipboardProbeStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSNotificationName name in @[UISceneDidActivateNotification, UIApplicationDidBecomeActiveNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; NFBClipboardProbeShow(); }];
            }
            NFBClipboardProbeShow();
        });
    }
}
