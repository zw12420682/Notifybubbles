#import "MWHeaders.h"

@interface MWWindowView : UIView

@property (nonatomic, strong) UIView *mainView;
@property (nonatomic, strong) NSString *bundleIdentifier;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) id oldRequester;
@property (nonatomic, strong) UIView *titleBar;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *minButton;
@property (nonatomic, strong) UIButton *maxButton;
@property (nonatomic, strong) UIView *sizeChanger;
@property (nonatomic, strong) NSTimer *mwGeometryTimer;
@property (nonatomic) NSUInteger mwLastOrientation;
@property (nonatomic) BOOL isOpen;
@property (nonatomic) CGPoint offset;
@property (nonatomic) CGPoint prevPos;
@property (nonatomic) CGRect oldFrame;
@property (nonatomic) CGRect prevFrame;
@property (nonatomic) BOOL isAspectLock;
@property (nonatomic) CGRect saveTitleLabelFrame;
@property (nonatomic) CGRect saveMinButtonFrame;
@property (nonatomic, strong) FBScene *scene;
@property (nonatomic, strong) id foregroundAssertion;
@property (nonatomic, strong) id processAssertion;

- (instancetype)initWithContentView:(UIView *)contentView identifier:(NSString *)identifier scene:(FBScene *)scene;
- (void)updateContentViewFrame:(CGRect)frame;
- (void)updateLayers;
- (NSUInteger)contentViewOrientation;
- (CGRect)contentViewFrame;

@end
