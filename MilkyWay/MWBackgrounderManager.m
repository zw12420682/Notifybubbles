#import "MWBackgrounderManager.h"

@implementation MWBackgrounderManager

+ (instancetype)sharedInstance {
    static MWBackgrounderManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _foregroundBundleIDs = [NSMutableArray array];
        _foregroundSceneIDs = [NSMutableArray array];
    }
    return self;
}

- (void)setForeground:(NSString *)bundleID enabled:(BOOL)enabled {
    if (!bundleID) return;
    if (enabled)
        [self.foregroundBundleIDs addObject:bundleID];
    else
        [self.foregroundBundleIDs removeObject:bundleID];
}

- (BOOL)isForeground:(NSString *)bundleID {
    if (!bundleID) return NO;
    return [self.foregroundBundleIDs containsObject:bundleID];
}

- (void)setForegroundSceneID:(NSString *)sceneID enabled:(BOOL)enabled {
    if (!sceneID) return;
    if (enabled)
        [self.foregroundSceneIDs addObject:sceneID];
    else
        [self.foregroundSceneIDs removeObject:sceneID];
}

- (BOOL)isForegroundScene:(NSString *)sceneID {
    if (!sceneID) return NO;
    return [self.foregroundSceneIDs containsObject:sceneID];
}

- (BOOL)shouldKeepForeground:(FBScene *)scene {
    NSString *identifier = MW_GetIvar(scene, "_identifier");
    if (!identifier && [scene respondsToSelector:@selector(identifier)]) {
        identifier = [scene identifier];
    }
    if (!identifier) return NO;

    for (NSString *bid in self.foregroundBundleIDs) {
        if ([identifier containsString:bid]) return YES;
    }
    for (NSString *sid in self.foregroundSceneIDs) {
        if ([sid isEqualToString:identifier]) return YES;
    }
    return NO;
}

@end
