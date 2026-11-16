#import "MWHeaders.h"

@interface MWSceneHelper : NSObject

+ (FBScene *)getFBScene:(NSString *)identifier;
+ (UIView *)createLayerHostView:(NSString *)identifier;
+ (void)wakeUpScene:(NSString *)identifier;
+ (void)sleepScene:(NSString *)identifier;
+ (void)startKeepAliveForBundleID:(NSString *)bundleID;
+ (void)stopKeepAliveForBundleID:(NSString *)bundleID;
+ (void)setSceneForeground:(FBScene *)scene foreground:(BOOL)fg;

@end
