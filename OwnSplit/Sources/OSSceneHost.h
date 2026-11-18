#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 把目标 App 的画面嵌进 UIView。
/// 使用 iOS scene layer container / FBSceneHostManager 嵌入实时画面。
@interface OSSceneHost : NSObject

@property (nonatomic, copy, readonly) NSString *bundleID;
@property (nonatomic, strong, readonly) UIView *view;
@property (nonatomic, assign, readonly, getter=isLive) BOOL live;
@property (nonatomic, copy, readonly, nullable) NSString *statusText;
@property (nonatomic, readonly) UIInterfaceOrientation sceneOrientation;
@property (nonatomic, copy, nullable) void (^onReconnectRequested)(OSSceneHost *host);
@property (nonatomic, copy, nullable) void (^onOrientationChanged)(OSSceneHost *host);

+ (BOOL)isSceneHostingAvailable;

- (instancetype)initWithBundleID:(NSString *)bundleID;
- (void)setHostedFrame:(CGRect)frame;
- (void)commitHostedFrame;
- (void)prepareForInput;
- (void)setSuspended:(BOOL)suspended;
- (void)retryAttach;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
