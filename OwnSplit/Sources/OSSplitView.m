#import "OSSplitView.h"
#import "OSSceneHost.h"
#import <QuartzCore/QuartzCore.h>
static const CGFloat kBar=34, kMinPane=150, kGap=5;
@interface OSSplitView ()
@property(nonatomic,copy,readwrite) NSString *primaryBundleID;
@property(nonatomic,copy,readwrite) NSString *secondaryBundleID;
@property(nonatomic,strong) UIView *topPane,*bottomPane,*divider;
@property(nonatomic,strong) UIButton *closeButton,*promoteButton;
@property(nonatomic,strong) OSSceneHost *primaryHost,*secondaryHost;
@property(nonatomic) CGPoint dragStart;
@property(nonatomic) CGFloat ratioStart;
@end
@implementation OSSplitView
- (instancetype)initWithPrimaryBundle:(NSString *)primary secondaryBundle:(NSString *)secondary ratio:(CGFloat)ratio {
 if((self=[super initWithFrame:CGRectZero])){ _primaryBundleID=[primary copy];_secondaryBundleID=[secondary copy];_ratio=MIN(.72,MAX(.28,ratio));self.clipsToBounds=YES;self.backgroundColor=UIColor.blackColor;
 _topPane=[UIView new];_bottomPane=[UIView new];_topPane.backgroundColor=UIColor.blackColor;_bottomPane.backgroundColor=UIColor.blackColor;[self addSubview:_topPane];[self addSubview:_bottomPane];
 _divider=[UIView new];_divider.backgroundColor=[UIColor colorWithWhite:.22 alpha:1];[self addSubview:_divider];
 _closeButton=[UIButton buttonWithType:UIButtonTypeSystem];[_closeButton setTitle:@"×" forState:UIControlStateNormal];_closeButton.titleLabel.font=[UIFont boldSystemFontOfSize:24];[_closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];_closeButton.backgroundColor=[UIColor colorWithWhite:0 alpha:.55];_closeButton.layer.cornerRadius=17;[_closeButton addTarget:self action:@selector(closeTap) forControlEvents:UIControlEventTouchUpInside];[self addSubview:_closeButton];
 _promoteButton=[UIButton buttonWithType:UIButtonTypeSystem];[_promoteButton setTitle:@"□" forState:UIControlStateNormal];_promoteButton.titleLabel.font=[UIFont systemFontOfSize:20];[_promoteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];_promoteButton.backgroundColor=[UIColor colorWithWhite:0 alpha:.55];_promoteButton.layer.cornerRadius=17;[_promoteButton addTarget:self action:@selector(promoteTap) forControlEvents:UIControlEventTouchUpInside];[self addSubview:_promoteButton];
 UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(dragDivider:)];[_divider addGestureRecognizer:pan];_divider.userInteractionEnabled=YES;
 }return self;
}
- (void)attachPrimaryHost:(OSSceneHost *)h { self.primaryHost=h;if(h){h.view.frame=self.topPane.bounds;h.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.topPane addSubview:h.view];} }
- (void)attachSecondaryHost:(OSSceneHost *)h { self.secondaryHost=h;if(h){h.view.frame=self.bottomPane.bounds;h.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.bottomPane addSubview:h.view];} }
- (OSSceneHost *)detachSecondaryHost { OSSceneHost*h=self.secondaryHost;[h.view removeFromSuperview];self.secondaryHost=nil;return h; }
- (void)layoutForBounds:(CGRect)b { self.frame=b;[self setNeedsLayout];[self layoutIfNeeded]; }
- (void)layoutSubviews { [super layoutSubviews];CGFloat H=self.bounds.size.height,W=self.bounds.size.width;if(H<1||W<1)return;CGFloat usable=MAX(0,H-kBar-kGap);CGFloat top=MIN(usable-kMinPane,MAX(kMinPane,usable*self.ratio));self.topPane.frame=CGRectMake(0,kBar,W,top);self.divider.frame=CGRectMake(0,kBar+top,W,kGap);self.bottomPane.frame=CGRectMake(0,kBar+top+kGap,W,MAX(0,usable-top));self.closeButton.frame=CGRectMake(W-42,2,32,30);self.promoteButton.frame=CGRectMake(W-82,2,32,30);self.primaryHost.view.frame=self.topPane.bounds;self.secondaryHost.view.frame=self.bottomPane.bounds;[self.primaryHost setHostedFrame:self.topPane.bounds];[self.secondaryHost setHostedFrame:self.bottomPane.bounds]; }
- (void)dragDivider:(UIPanGestureRecognizer*)g {if(g.state==UIGestureRecognizerStateBegan){self.dragStart=[g locationInView:self];self.ratioStart=self.ratio;}else if(g.state==UIGestureRecognizerStateChanged){CGFloat usable=MAX(1,self.bounds.size.height-kBar-kGap);CGFloat y=[g locationInView:self].y-self.dragStart.y;self.ratio=MIN(.72,MAX(.28,self.ratioStart+y/usable));[self setNeedsLayout];[self layoutIfNeeded];}else if(g.state==UIGestureRecognizerStateEnded){[self.primaryHost commitHostedFrame];[self.secondaryHost commitHostedFrame];if(self.onRatioChanged)self.onRatioChanged(self.ratio);}}
- (void)closeTap {if(self.onClose)self.onClose();}
- (void)promoteTap {if(self.onPromoteSecondaryToFloating)self.onPromoteSecondaryToFloating(self.secondaryBundleID);}
- (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion {void(^done)(void)=^{[self.primaryHost invalidate];[self.secondaryHost invalidate];[self removeFromSuperview];if(completion)completion();};if(animated)[UIView animateWithDuration:.2 animations:^{self.alpha=0;} completion:^(BOOL f){done();}];else done();}
@end
