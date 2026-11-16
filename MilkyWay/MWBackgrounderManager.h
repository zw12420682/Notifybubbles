#import "MWHeaders.h"

@interface MWBackgrounderManager : NSObject

@property (nonatomic, strong) NSMutableArray *foregroundBundleIDs;
@property (nonatomic, strong) NSMutableArray *foregroundSceneIDs;

+ (instancetype)sharedInstance;
- (void)setForeground:(NSString *)bundleID enabled:(BOOL)enabled;
- (BOOL)isForeground:(NSString *)bundleID;
- (void)setForegroundSceneID:(NSString *)sceneID enabled:(BOOL)enabled;
- (BOOL)isForegroundScene:(NSString *)sceneID;
- (BOOL)shouldKeepForeground:(FBScene *)scene;

@end
