#import <UIKit/UIKit.h>
#import <os/log.h>

@interface NFBTransferDragWindow : UIWindow
@end
@implementation NFBTransferDragWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}
@end

@interface NFBTransferDragPreview : UIViewController <UIDropInteractionDelegate, UIDragInteractionDelegate>
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UIView *dropTarget;
@property(nonatomic,strong) UIImageView *source;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSUInteger attempts;
@end

static UIImage *NFBTransferSampleImage(void) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(192, 192)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemIndigoColor setFill];
        [ctx fillRect:CGRectMake(0, 0, 192, 192)];
        [@"拖放测试" drawAtPoint:CGPointMake(36, 76)
                 withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:30], NSForegroundColorAttributeName:UIColor.whiteColor}];
    }];
}

@implementation NFBTransferDragPreview
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    [toggle setTitle:@"拖放测试" forState:UIControlStateNormal];
    [toggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    toggle.backgroundColor = UIColor.systemIndigoColor;
    toggle.accessibilityLabel = @"打开或收起拖放测试";
    toggle.layer.cornerRadius = 12;
    [toggle addTarget:self action:@selector(nfbTogglePanel) forControlEvents:UIControlEventTouchUpInside];
    self.panel = [UIView new];
    self.panel.hidden = YES;
    self.panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.panel.layer.cornerRadius = 16;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = UIColor.systemIndigoColor.CGColor;
    self.dropTarget = [UIView new];
    self.dropTarget.backgroundColor = [UIColor.systemIndigoColor colorWithAlphaComponent:0.15];
    self.dropTarget.layer.cornerRadius = 10;
    self.label = [UILabel new];
    self.label.text = @"图片拖到这里";
    self.label.font = [UIFont boldSystemFontOfSize:14];
    self.label.numberOfLines = 2;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.source = [[UIImageView alloc] initWithImage:NFBTransferSampleImage()];
    self.source.contentMode = UIViewContentModeScaleAspectFit;
    self.source.userInteractionEnabled = YES;
    self.source.accessibilityLabel = @"按住这张图向外拖";
    self.source.layer.cornerRadius = 8;
    self.source.clipsToBounds = YES;
    [self.view addSubview:toggle];
    [self.view addSubview:self.panel];
    [self.panel addSubview:self.dropTarget];
    [self.dropTarget addSubview:self.label];
    [self.panel addSubview:self.source];
    for (UIView *v in @[toggle,self.panel,self.dropTarget,self.label,self.source]) v.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [toggle.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [toggle.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor constant:38],
        [toggle.widthAnchor constraintEqualToConstant:86], [toggle.heightAnchor constraintEqualToConstant:42],
        [self.panel.leadingAnchor constraintEqualToAnchor:toggle.leadingAnchor],
        [self.panel.bottomAnchor constraintEqualToAnchor:toggle.topAnchor constant:-6],
        [self.panel.widthAnchor constraintEqualToConstant:156], [self.panel.heightAnchor constraintEqualToConstant:138],
        [self.dropTarget.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:8],
        [self.dropTarget.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:8],
        [self.dropTarget.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-8],
        [self.dropTarget.heightAnchor constraintEqualToConstant:54],
        [self.label.leadingAnchor constraintEqualToAnchor:self.dropTarget.leadingAnchor constant:4],
        [self.label.trailingAnchor constraintEqualToAnchor:self.dropTarget.trailingAnchor constant:-4],
        [self.label.centerYAnchor constraintEqualToAnchor:self.dropTarget.centerYAnchor],
        [self.source.centerXAnchor constraintEqualToAnchor:self.panel.centerXAnchor],
        [self.source.topAnchor constraintEqualToAnchor:self.dropTarget.bottomAnchor constant:6],
        [self.source.widthAnchor constraintEqualToConstant:62], [self.source.heightAnchor constraintEqualToConstant:62],
    ]];
    [self.dropTarget addInteraction:[[UIDropInteraction alloc] initWithDelegate:self]];
    UIDragInteraction *drag = [[UIDragInteraction alloc] initWithDelegate:self];
    drag.enabled = YES;
    [self.source addInteraction:drag];
}
- (void)nfbTogglePanel { self.panel.hidden = !self.panel.hidden; }
- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    (void)interaction;
    return !self.loading && !session.localDragSession && [session canLoadObjectsOfClass:UIImage.class];
}
- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction sessionDidUpdate:(id<UIDropSession>)session {
    BOOL accept = [self dropInteraction:interaction canHandleSession:session];
    if (accept) self.label.text = @"松手复制图片";
    return [[UIDropProposal alloc] initWithDropOperation:accept ? UIDropOperationCopy : UIDropOperationCancel];
}
- (void)dropInteraction:(UIDropInteraction *)interaction sessionDidEnd:(id<UIDropSession>)session {
    (void)interaction; (void)session;
    if (!self.loading && !self.attempts) self.label.text = @"图片拖到这里";
}
- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {
    (void)interaction;
    if (self.loading || session.localDragSession) return;
    NSItemProvider *provider = session.items.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:UIImage.class]) return;
    self.loading = YES;
    NSUInteger attempt = ++self.attempts;
    self.label.text = @"读取图片中…";
    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        UIImage *image = !error && [(id)object isKindOfClass:UIImage.class] ? (UIImage *)object : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            NFBTransferDragPreview *vc = weakSelf;
            if (!vc || !vc.loading || vc.attempts != attempt) return;
            vc.loading = NO;
            if (image) vc.source.image = image;
            vc.label.text = image ? @"拖入成功\n按住下图可拖出" : @"未能读取图片";
            os_log(OS_LOG_DEFAULT, "[NFBTransferDragProbe] incoming image success=%d", image != nil);
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NFBTransferDragPreview *vc = weakSelf;
        if (!vc || !vc.loading || vc.attempts != attempt) return;
        vc.loading = NO;
        vc.label.text = @"读取图片超时";
    });
}
- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction itemsForBeginningSession:(id<UIDragSession>)session {
    (void)interaction; (void)session;
    UIImage *image = self.source.image;
    if (!image) return @[];
    NSItemProvider *p = [[NSItemProvider alloc] initWithObject:image];
    p.suggestedName = @"拖放测试";
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:p];
    os_log(OS_LOG_DEFAULT, "[NFBTransferDragProbe] outgoing drag began");
    return @[item];
}
- (BOOL)dragInteraction:(UIDragInteraction *)interaction sessionAllowsMoveOperation:(id<UIDragSession>)session {
    (void)interaction; (void)session;
    return NO;
}
- (void)dragInteraction:(UIDragInteraction *)interaction session:(id<UIDragSession>)session didEndWithOperation:(UIDropOperation)operation {
    (void)interaction; (void)session;
    os_log(OS_LOG_DEFAULT, "[NFBTransferDragProbe] outgoing operation=%lu", (unsigned long)operation);
}
@end

static NFBTransferDragWindow *NFBTransferProbeWindow;
static void NFBTransferDragShow(void) {
    if (NFBTransferProbeWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive &&
            ((UIWindowScene *)s).screen == UIScreen.mainScreen) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    NFBTransferProbeWindow = [[NFBTransferDragWindow alloc] initWithWindowScene:scene];
    NFBTransferProbeWindow.windowLevel = UIWindowLevelAlert + 1;
    NFBTransferProbeWindow.backgroundColor = UIColor.clearColor;
    NFBTransferProbeWindow.rootViewController = [NFBTransferDragPreview new];
    NFBTransferProbeWindow.hidden = NO; // No key-window or keyboard ownership.
}

__attribute__((constructor)) static void NFBTransferDragStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; NFBTransferDragShow(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; NFBTransferDragShow(); }];
            NFBTransferDragShow();
        });
    }
}
