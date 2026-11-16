#import "MWHeaders.h"

@interface MWPassthroughView : UIView
@end

@interface MWPassthroughWindow : UIWindow

@property (nonatomic) NSInteger initOrientation;

+ (instancetype)sharedInstance;
+ (void)setSharedInstance:(MWPassthroughWindow *)instance;
+ (MWPassthroughWindow *)keyboardWindow;
+ (void)setKeyboardWindow:(MWPassthroughWindow *)window;
+ (BOOL)isWindowed:(NSString *)bundleID;
+ (void)addWindowedId:(NSString *)bundleID;
+ (void)removeWindowedId:(NSString *)bundleID;
+ (void)notifyUpdateLayers;

- (instancetype)initWithNoRotation;

@end
