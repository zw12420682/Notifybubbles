#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Helper for ivar access under ARC
NS_INLINE id MW_GetIvar(id obj, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return nil;
    void *ptr = (__bridge void *)obj;
    return (__bridge id)(*(void **)((char *)ptr + ivar_getOffset(ivar)));
}

NS_INLINE void MW_SetIvarBool(id obj, const char *name, BOOL val) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return;
    void *ptr = (__bridge void *)obj;
    *(BOOL *)((char *)ptr + ivar_getOffset(ivar)) = val;
}

// FrontBoard
@interface FBScene : NSObject
@property (nonatomic, readonly) NSString *identifier;
- (id)mutableSettings;
- (id)settings;
- (id)layerManager;
- (void)updateSettings:(id)settings withTransitionContext:(id)ctx completion:(id)completion;
- (void)updateSettings:(id)settings withTransitionContext:(id)ctx;
@end

@interface FBSceneManager : NSObject
+ (instancetype)sharedInstance;
@end

@interface FBSMutableSceneSettings : NSObject
@property (nonatomic, getter=isForeground) BOOL foreground;
- (id)mutableCopy;
@end

@interface UIMutableApplicationSceneSettings : NSObject
- (void)setDeactivationReasons:(unsigned long long)reasons;
- (unsigned long long)deactivationReasons;
@end

// RunningBoard process assertions (prevents kernel-level suspension)
@interface RBSTarget : NSObject
+ (instancetype)targetWithPid:(int)pid;
+ (instancetype)currentProcess;
@end

@interface RBSLegacyAttribute : NSObject
+ (instancetype)attributeWithReason:(NSUInteger)reason flags:(NSUInteger)flags;
@end

@interface RBSAssertion : NSObject
- (instancetype)initWithExplanation:(NSString *)explanation target:(RBSTarget *)target attributes:(NSArray *)attributes;
- (BOOL)acquireWithError:(NSError **)error;
- (void)invalidate;
@end

@interface RBSConnection : NSObject
+ (instancetype)sharedInstance;
@end

// Mach task API for resuming suspended processes
#include <mach/mach.h>

// BKS flags
enum {
    BKSProcessAssertionPreventTaskSuspend = (1 << 0),
    BKSProcessAssertionPreventTaskThrottleDown = (1 << 1),
    BKSProcessAssertionWantsForegroundResourcePriority = (1 << 3),
    BKSProcessAssertionPreventThrottleDownUI = (1 << 5),
};
enum {
    BKSProcessAssertionReasonBackgroundUI = 7,
};

@interface _UISceneHostingActivationStateHostComponent : NSObject
- (void)evaluateActivationState;
- (id)foregroundAssertionForReason:(id)reason;
- (id)hostScene;
- (void)setForeground:(BOOL)fg;
@end

@interface FBSceneLayerManager : NSObject
- (NSArray *)layers;
@end

// SpringBoard
@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *displayName;
- (BOOL)isMedusaCapable;
- (id)processState;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)identifier;
@end

@interface SBAppLayout : NSObject
+ (id)homeScreenAppLayout;
- (id)rolesToLayoutItemsMap;
- (NSString *)mw_bundleIdentifier;
- (NSString *)mw_sceneIdentifier;
- (NSArray *)allItems;
- (id)centerItem;
- (id)floatingItem;
@end

@interface SBFluidSwitcherItemContainer : UIView
- (id)appLayout;
- (id)_pageView;
@end

@interface SBDisplayItem : NSObject
+ (id)displayItemWithType:(long long)type bundleIdentifier:(NSString *)bundleID uniqueIdentifier:(NSString *)uniqueID;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *uniqueIdentifier;
@end

@interface SBMainSwitcherViewController : UIViewController
+ (instancetype)sharedInstance;
- (BOOL)_dismissSwitcherNoninteractivelyToAppLayout:(id)layout dismissFloatingSwitcher:(BOOL)dismiss animated:(BOOL)animated;
- (void)_addAppLayoutToFront:(id)layout;
@end

@interface SBAppSwitcherPageView : UIView
- (id)appLayout;
@end

@interface SpringBoard : UIApplication
- (void)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@interface SBIconView : UIView
- (NSString *)applicationBundleIdentifier;
- (NSString *)applicationBundleIdentifierForShortcuts;
@end

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *bundleIdentifierToLaunch;
@end

// UIKit Private
@interface _UISceneLayerHostContainerView : UIView
- (instancetype)initWithScene:(id)scene;
- (instancetype)initWithScene:(id)scene debugDescription:(id)desc;
- (id)_createHostViewForLayer:(id)layer;
- (id)scene;
- (id)hostedLayers;
@end

@interface _UIContextLayerHostView : UIView
- (instancetype)initWithSceneLayer:(id)layer;
@end

@interface _UIKeyboardLayerHostView : UIView
@end

// UIView private additions
@interface UIView (MWPrivate)
- (id)_createHostViewForLayer:(id)layer;
@end

// Process state
@interface FBProcessState : NSObject
- (BOOL)isRunning;
@end

// Forward declarations for our classes
@class MWWindowView;
@class MWPassthroughWindow;
@class MWSceneHelper;
@class MWBackgrounderManager;
@class MWThemeManager;
