#import <UIKit/UIKit.h>
@class OSSceneHost;
@interface OSSplitView : UIView
@property(nonatomic,copy,readonly) NSString *primaryBundleID;
@property(nonatomic,copy,readonly) NSString *secondaryBundleID;
@property(nonatomic,strong,readonly) OSSceneHost *primaryHost;
@property(nonatomic,strong,readonly) OSSceneHost *secondaryHost;
@property(nonatomic,strong,readonly) UIView *topPane;
@property(nonatomic) CGFloat ratio;
@property(nonatomic,copy) void (^onClose)(void);
@property(nonatomic,copy) void (^onRatioChanged)(CGFloat);
@property(nonatomic,copy) void (^onPromoteSecondaryToFloating)(NSString *bundleID);
- (instancetype)initWithPrimaryBundle:(NSString *)primary secondaryBundle:(NSString *)secondary ratio:(CGFloat)ratio;
- (void)attachPrimaryHost:(OSSceneHost *)host;
- (void)attachSecondaryHost:(OSSceneHost *)host;
- (OSSceneHost *)detachSecondaryHost;
- (void)layoutForBounds:(CGRect)bounds;
- (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end
