#import "MWSceneHelper.h"

@implementation MWSceneHelper

#pragma mark - Scene Manager Access

+ (id)_sceneManager {
    // iOS 26+: SBMainWorkspace.sharedInstance.sceneManager
    Class mainWS = NSClassFromString(@"SBMainWorkspace");
    if (mainWS && [mainWS respondsToSelector:@selector(sharedInstance)]) {
        id workspace = [mainWS sharedInstance];
        if (workspace && [workspace respondsToSelector:@selector(sceneManager)]) {
            id mgr = [workspace performSelector:@selector(sceneManager)];
            if (mgr) return mgr;
        }
    }
    // Fallback: FBSceneManager.sharedInstance
    Class fbMgr = NSClassFromString(@"FBSceneManager");
    if (fbMgr && [fbMgr respondsToSelector:@selector(sharedInstance)])
        return [fbMgr sharedInstance];
    return nil;
}

#pragma mark - Scene Lookup (multi-strategy)

+ (FBScene *)getFBScene:(NSString *)identifier {
    if (!identifier) return nil;

    id manager = [self _sceneManager];
    if (!manager) return nil;

    // Strategy 1: Try known dictionary ivars on manager
    for (NSString *ivarName in @[@"_scenesByID", @"_scenes"]) {
        id dict = MW_GetIvar(manager, [ivarName UTF8String]);
        if ([dict isKindOfClass:[NSDictionary class]]) {
            FBScene *scene = [self _findScene:identifier inDict:dict];
            if (scene) return scene;
        }
    }

    // Strategy 2: Try _workspace sub-object (iOS 15-16)
    id workspace = MW_GetIvar(manager, "_workspace");
    if (workspace) {
        for (NSString *ivarName in @[@"_allScenesByID", @"_scenesByIdentifier", @"_scenesByID"]) {
            id dict = MW_GetIvar(workspace, [ivarName UTF8String]);
            if ([dict isKindOfClass:[NSDictionary class]]) {
                FBScene *scene = [self _findScene:identifier inDict:dict];
                if (scene) return scene;
            }
        }
    }

    // Strategy 3: iOS 26 scene handle maps
    for (NSString *ivarName in @[@"_persistentMapSceneIdentityToSceneHandle",
                                  @"_transientMapSceneIdentityToSceneHandle"]) {
        id map = MW_GetIvar(manager, [ivarName UTF8String]);
        if ([map respondsToSelector:@selector(allValues)]) {
            for (id handle in [map allValues]) {
                NSString *sid = nil;
                if ([handle respondsToSelector:@selector(sceneIdentifier)])
                    sid = [handle performSelector:@selector(sceneIdentifier)];
                if (sid && [sid containsString:identifier]) {
                    if ([handle respondsToSelector:@selector(scene)]) {
                        id scene = [handle scene];
                        if (scene) return scene;
                    }
                }
            }
        }
    }

    // Strategy 4: allScenes (NSSet on SBSceneManager)
    if ([manager respondsToSelector:@selector(allScenes)]) {
        for (id scene in [manager performSelector:@selector(allScenes)]) {
            if ([scene respondsToSelector:@selector(identifier)]) {
                NSString *sid = [scene identifier];
                if (sid && [sid containsString:identifier])
                    return scene;
            }
        }
    }

    // Strategy 5: Deep ivar scan - find any NSDictionary with FBScene-like objects
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(manager), &count);
    for (unsigned int i = 0; i < count; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (type && type[0] == '@') {
            id value = MW_GetIvar(manager, ivar_getName(ivars[i]));
            if ([value isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)value;
                for (NSString *key in dict) {
                    if (![key isKindOfClass:[NSString class]]) continue;
                    if ([key containsString:identifier]) {
                        id candidate = dict[key];
                        // Check if it's an FBScene
                        if ([candidate respondsToSelector:@selector(layerManager)] ||
                            [candidate respondsToSelector:@selector(identifier)]) {
                            free(ivars);
                            return candidate;
                        }
                        // Check if it's an SBSceneHandle
                        if ([candidate respondsToSelector:@selector(scene)]) {
                            id scene = [candidate scene];
                            if (scene) { free(ivars); return scene; }
                        }
                    }
                }
            }
        }
    }
    if (ivars) free(ivars);

    // Strategy 6: SBSceneManager class method
    Class sbSceneMgr = NSClassFromString(@"SBSceneManager");
    if (sbSceneMgr && [sbSceneMgr respondsToSelector:@selector(existingSceneHandleForSceneIdentity:)]) {
        Class identityProvider = NSClassFromString(@"SBSceneIdentityProvider");
        if (identityProvider && [identityProvider respondsToSelector:@selector(identityForIdentifier:)]) {
            id identity = [identityProvider performSelector:@selector(identityForIdentifier:) withObject:identifier];
            if (identity) {
                id handle = [sbSceneMgr performSelector:@selector(existingSceneHandleForSceneIdentity:) withObject:identity];
                if (handle && [handle respondsToSelector:@selector(scene)])
                    return [handle scene];
            }
        }
    }

    return nil;
}

+ (FBScene *)_findScene:(NSString *)identifier inDict:(NSDictionary *)dict {
    if (!dict || ![dict count]) return nil;
    id scene = dict[identifier];
    if (scene) return scene;
    for (NSString *key in [dict allKeys]) {
        if ([key containsString:identifier])
            return dict[key];
    }
    return nil;
}

#pragma mark - Layer Host View Creation

+ (UIView *)createLayerHostView:(NSString *)identifier {
    FBScene *scene = [self getFBScene:identifier];
    if (!scene) return nil;

    Class containerClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    if (containerClass) {
        _UISceneLayerHostContainerView *container = nil;
        // iOS 26: initWithScene:debugDescription:
        if ([containerClass instancesRespondToSelector:@selector(initWithScene:debugDescription:)])
            container = [[containerClass alloc] initWithScene:scene debugDescription:@"MilkyWayReborn"];
        // iOS 15-18: initWithScene:
        else if ([containerClass instancesRespondToSelector:@selector(initWithScene:)])
            container = [[containerClass alloc] initWithScene:scene];
        if (container) {
            id containerScene = [container scene];
            if (containerScene && [containerScene respondsToSelector:@selector(layerManager)]) {
                id layerManager = [containerScene layerManager];
                NSArray *layers = [layerManager layers];
                for (id layer in layers) {
                    if ([container respondsToSelector:@selector(_createHostViewForLayer:)]) {
                        UIView *hostView = [container _createHostViewForLayer:layer];
                        if (hostView) {
                            hostView.frame = container.frame;
                            [container addSubview:hostView];
                        }
                    }
                }
            }
            container.frame = [UIScreen mainScreen].bounds;
            return container;
        }
    }

    return nil;
}

#pragma mark - Scene Foreground Management

+ (void)setSceneForeground:(FBScene *)scene foreground:(BOOL)fg {
    if (!scene) return;

    @try {
        // Use [scene settings] → mutableCopy → setForeground: → updateSettings
        // (IDA-verified pattern for iOS 26)
        if ([scene respondsToSelector:@selector(settings)]) {
            id settings = [scene settings];
            if ([settings respondsToSelector:@selector(mutableCopy)]) {
                id mutableSettings = [settings mutableCopy];
                if ([mutableSettings respondsToSelector:@selector(setForeground:)]) {
                    [mutableSettings setForeground:fg];
                    // Use 2-arg version first (Aerial/iOS14Fix approach)
                    if ([scene respondsToSelector:@selector(updateSettings:withTransitionContext:)])
                        [scene updateSettings:mutableSettings withTransitionContext:nil];
                    else if ([scene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)])
                        [scene updateSettings:mutableSettings withTransitionContext:nil completion:nil];
                    return;
                }
            }
        }

        // Fallback: direct mutableSettings ivar (iOS 13-14)
        id mutableSettings = MW_GetIvar(scene, "_mutableSettings");
        if (mutableSettings) {
            MW_SetIvarBool(mutableSettings, "_foreground", fg);
            if ([scene respondsToSelector:@selector(updateSettings:withTransitionContext:completion:)])
                [scene updateSettings:mutableSettings withTransitionContext:nil completion:nil];
        }
    } @catch (NSException *e) {
        NSLog(@"[MilkyWayReborn] setSceneForeground exception: %@", e);
    }
}

+ (void)wakeUpScene:(NSString *)identifier {
    FBScene *scene = [self getFBScene:identifier];
    [self setSceneForeground:scene foreground:YES];
}

+ (void)sleepScene:(NSString *)identifier {
    FBScene *scene = [self getFBScene:identifier];
    [self setSceneForeground:scene foreground:NO];
}

#pragma mark - Keep-alive timer (Aerial approach)

static NSMutableDictionary *_keepAliveTimers = nil;

+ (void)startKeepAliveForBundleID:(NSString *)bundleID {
    if (!bundleID) return;
    if (!_keepAliveTimers) _keepAliveTimers = [NSMutableDictionary new];

    // Stop existing timer if any
    [self stopKeepAliveForBundleID:bundleID];

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_walltime(NULL, 0), 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        FBScene *scene = [self getFBScene:bundleID];
        if (!scene) return;
        [self setSceneForeground:scene foreground:YES];
    });
    dispatch_resume(timer);
    _keepAliveTimers[bundleID] = timer;
    NSLog(@"[MilkyWayReborn] Keep-alive timer started for %@", bundleID);
}

+ (void)stopKeepAliveForBundleID:(NSString *)bundleID {
    if (!bundleID || !_keepAliveTimers) return;
    dispatch_source_t timer = _keepAliveTimers[bundleID];
    if (timer) {
        dispatch_source_cancel(timer);
        [_keepAliveTimers removeObjectForKey:bundleID];
        NSLog(@"[MilkyWayReborn] Keep-alive timer stopped for %@", bundleID);
    }
}

@end
