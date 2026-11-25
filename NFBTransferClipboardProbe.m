#import <UIKit/UIKit.h>
#import <notify.h>
#import <time.h>
#import "NFBDirectPaste.h"
#import <stdatomic.h>

// Main invalidates this generation before queued work may touch the clipboard.
static _Atomic unsigned long NFBClipboardGeneration;

@interface NFBClipboardProbeWindow : UIWindow
@end
@implementation NFBClipboardProbeWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return v == self || v == self.rootViewController.view ? nil : v;
}
@end

@interface NFBClipboardProbeController : UIViewController
@property(nonatomic,strong) NSMutableArray<NSString *> *history;
@property(nonatomic,strong) UIStackView *records;
@property(nonatomic,strong) UIStackView *panel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) dispatch_queue_t clipboardQueue;
@property(nonatomic) int notifyToken;
@property(nonatomic) BOOL listening;
@property(nonatomic) BOOL writing;
- (void)nfbRender;
- (void)nfbStopListening;
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
    self.clipboardQueue = dispatch_queue_create("local.notifybubbles.clipboard.text-probe", DISPATCH_QUEUE_SERIAL);
    UIButton *toggle = [self nfbButton:@"剪贴板测试" action:@selector(nfbToggle)];
    toggle.backgroundColor = UIColor.systemIndigoColor;
    [toggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    toggle.layer.cornerRadius = 10;
    self.status = [UILabel new];
    self.status.text = @"只收录「Minis测试」开头的文字";
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
- (void)nfbStopListening {
    atomic_fetch_add(&NFBClipboardGeneration, 1);
    if (self.listening) (void)notify_cancel(self.notifyToken);
    self.listening = NO;
    self.writing = NO;
}
- (void)nfbClearOnLock:(NSNotification *)note {
    (void)note;
    [self nfbStopListening];
    [self.history removeAllObjects]; [self nfbRender];
    self.panel.hidden = YES;
    self.status.text = @"测试已结束";
}
- (void)nfbToggle { self.panel.hidden = !self.panel.hidden; }
- (void)nfbStart {
    if (self.listening || self.writing || !UIApplication.sharedApplication.protectedDataAvailable) return;
    [self.history removeAllObjects]; [self nfbRender];
    const unsigned long generation = atomic_fetch_add(&NFBClipboardGeneration, 1) + 1;
    const NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 60;
    __block NSInteger seen = -1; // Confined to the serial clipboard queue.
    __weak typeof(self) weakSelf = self;
    int token = 0;
    uint32_t result = notify_register_dispatch("com.apple.pasteboard.notify.changed", &token, self.clipboardQueue, ^(int delivered) {
        (void)delivered;
        @autoreleasepool {
            if (atomic_load(&NFBClipboardGeneration) != generation || NSProcessInfo.processInfo.systemUptime >= deadline) return;
            UIPasteboard *pb = UIPasteboard.generalPasteboard;
            NSInteger count = pb.changeCount;
            if (count == seen) return;
            seen = count;
            if (!pb.hasStrings || atomic_load(&NFBClipboardGeneration) != generation) return;
            NSString *text = pb.string;
            if (text.length > 128 || ![text hasPrefix:@"Minis测试"] || pb.changeCount != count) return;
            NSString *snapshot = [text copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                NFBClipboardProbeController *vc = weakSelf;
                if (!vc || !vc.listening || atomic_load(&NFBClipboardGeneration) != generation ||
                    !UIApplication.sharedApplication.protectedDataAvailable || [vc.history containsObject:snapshot]) return;
                [vc.history insertObject:snapshot atIndex:0];
                if (vc.history.count > 3) [vc.history removeLastObject];
                vc.status.text = @"已记录测试文字";
                [vc nfbRender];
            });
        }
    });
    if (result != NOTIFY_STATUS_OK) { self.status.text = @"未能注册剪贴板通知"; return; }
    self.notifyToken = token;
    self.listening = YES;
    self.status.text = @"测试中：到其他 App 复制文字";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NFBClipboardProbeController *vc = weakSelf;
        if (!vc || atomic_load(&NFBClipboardGeneration) != generation) return;
        [vc nfbStopListening];
        vc.status.text = @"采集结束，仍可点记录复制";
    });
}
- (void)nfbRender {
    for (UIView *v in [self.records.arrangedSubviews copy]) {
        [self.records removeArrangedSubview:v]; [v removeFromSuperview];
    }
    [self.history enumerateObjectsUsingBlock:^(NSString *entry, NSUInteger i, BOOL *stop) {
        (void)stop;
        UIButton *b = [self nfbButton:[NSString stringWithFormat:@"%lu. %@",(unsigned long)(i+1),entry] action:@selector(nfbCopy:)];
        b.tag = (NSInteger)i;
        [self.records addArrangedSubview:b];
    }];
}
- (void)nfbCopy:(UIButton *)button {
    if (self.writing || !UIApplication.sharedApplication.protectedDataAvailable ||
        button.tag < 0 || (NSUInteger)button.tag >= self.history.count) return;
    NSString *text = self.history[(NSUInteger)button.tag];
    unsigned long generation = atomic_load(&NFBClipboardGeneration);
    NSDictionary *initialTarget = NFBPasteFrontTarget();
    self.writing = YES;
    self.status.text = @"正在复制…";
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.clipboardQueue, ^{
        if (atomic_load(&NFBClipboardGeneration) != generation) return;
        UIPasteboard *pb = UIPasteboard.generalPasteboard;
        [pb setItems:@[@{@"public.utf8-plain-text":text}] options:@{UIPasteboardOptionLocalOnly:@YES}];
        const NSInteger count = initialTarget ? pb.changeCount : 0;
        const BOOL verified = initialTarget && [pb.string isEqualToString:text] && pb.changeCount == count;
        dispatch_async(dispatch_get_main_queue(), ^{
            NFBClipboardProbeController *vc = weakSelf;
            if (!vc || atomic_load(&NFBClipboardGeneration) != generation) return;
            NSDictionary *target = verified ? NFBPasteFrontTarget() : nil;
            if (!target || ![target isEqualToDictionary:initialTarget]) {
                vc.writing = NO;
                vc.status.text = @"已复制，请手动粘贴";
                return;
            }
            NSMutableDictionary *packet = [target mutableCopy];
            packet[@"deadline"] = @(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) + 400000000ULL);
            packet[@"changeCount"] = @(count);
            dispatch_async(vc.clipboardQueue, ^{
                BOOL sent = atomic_load(&NFBClipboardGeneration) == generation && NFBPasteRequest(packet);
                dispatch_async(dispatch_get_main_queue(), ^{
                    NFBClipboardProbeController *controller = weakSelf;
                    if (!controller || atomic_load(&NFBClipboardGeneration) != generation) return;
                    controller.writing = NO;
                    controller.status.text = sent ? @"已请求系统粘贴，请查看输入框" : @"已复制，请手动粘贴";
                    if (sent) controller.panel.hidden = YES;
                });
            });
        });
    });
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
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ NFBPasteInstallAppHelper(); });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSNotificationName name in @[UISceneDidActivateNotification, UIApplicationDidBecomeActiveNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; NFBClipboardProbeShow(); }];
            }
            NFBClipboardProbeShow();
        });
    }
}
