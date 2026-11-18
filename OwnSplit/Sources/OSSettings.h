#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OSActivationGesture) {
    OSActivationGestureEdgeSwipe = 0,
    OSActivationGestureThreeFingerSwipeUp = 1,
    OSActivationGestureStatusBarDoubleTap = 2,
    OSActivationGestureHomeIndicatorLongPress = 3,
    OSActivationGestureIconSwipeUp = 4,     // 主屏幕图标上滑
    OSActivationGestureIconLongPress = 5,   // 主屏幕图标长按菜单
};

@interface OSSettings : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) CGFloat floatingOpacity;   // 0.5 – 1.0
@property (nonatomic, readonly) CGFloat floatingCornerRadius;
@property (nonatomic, readonly) CGSize defaultFloatingSize;
@property (nonatomic, readonly) BOOL showBorder;
@property (nonatomic, readonly) BOOL hapticFeedback;
@property (nonatomic, readonly) BOOL rememberLastApps;
@property (nonatomic, readonly) BOOL allowLandscape;
@property (nonatomic, readonly) NSInteger maxFloatingWindows;
@property (nonatomic, readonly) NSArray<NSNumber *> *enabledGestures; // OSActivationGesture
@property (nonatomic, readonly) NSArray<NSString *> *blacklist;       // bundle IDs
@property (nonatomic, readonly) NSArray<NSString *> *favorites;       // bundle IDs
@property (nonatomic, readonly) CGFloat edgeSwipeSensitivity;         // 0.0 – 1.0
@property (nonatomic, readonly) BOOL animateTransitions;
@property (nonatomic, readonly) CGRect lastFloatingFrame;
@property (nonatomic, readonly) CGFloat lastSplitRatio;
@property (nonatomic, readonly) NSString *lastPrimaryBundleID;
@property (nonatomic, readonly) NSString *lastSecondaryBundleID;
- (void)setLastSplitRatio:(CGFloat)ratio;
- (void)setLastPrimaryBundleID:(NSString *)bundleID;
- (void)setLastSecondaryBundleID:(NSString *)bundleID;

- (void)reload;
- (void)setLastFloatingFrame:(CGRect)frame;
- (BOOL)isBundleBlacklisted:(NSString *)bundleID;
- (BOOL)isGestureEnabled:(OSActivationGesture)gesture;

@end

// Darwin notification posted when prefs change
FOUNDATION_EXPORT NSString * const kOSSettingsChangedNotification;

NS_ASSUME_NONNULL_END
