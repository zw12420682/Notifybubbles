#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OSSceneHost;

/// Hosts a second app scene inside a draggable / resizable floating chrome.
@interface OSFloatingWindow : UIView

@property (nonatomic, copy, readonly) NSString *bundleID;
@property (nonatomic, strong, readonly, nullable) OSSceneHost *sceneHost;
@property (nonatomic, assign) CGFloat contentOpacity;
@property (nonatomic, assign) CGFloat cornerRadiusValue;
@property (nonatomic, assign) BOOL showsBorder;
@property (nonatomic, copy, nullable) void (^onClose)(OSFloatingWindow *window);
@property (nonatomic, copy, nullable) void (^onFocus)(OSFloatingWindow *window);
@property (nonatomic, copy, nullable) void (^onFrameChanged)(OSFloatingWindow *window, CGRect frame);

- (instancetype)initWithBundleID:(NSString *)bundleID frame:(CGRect)frame;
- (void)attachSceneHost:(OSSceneHost *)host;
- (nullable OSSceneHost *)detachSceneHost;
- (void)commitSceneLayout;
- (void)setActive:(BOOL)active animated:(BOOL)animated;
- (void)bringToFront;
- (void)closeAnimated:(BOOL)animated completion:(void (^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
