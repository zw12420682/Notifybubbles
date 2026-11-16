#import "NFBSplitCoordinator.h"
#import "NFBWindowControls.h"
#import "NFBDesktopHost.h"
#import "NFBWindowState.h"
#import "NFBDebugLog.h"

@interface NFBOpenSplitBackend : NSObject <NFBSplitBackend> @end
@implementation NFBOpenSplitBackend
- (NSString *)identifier { return @"open-compat"; }
- (NSString *)sceneIdentity { return NFBCurrentWindowState().sceneKey ?: @"unknown"; }
- (BOOL)applyMovieEnabled:(BOOL)enabled { return NFBUpdateMovieMode(enabled); }
- (void)settleMovieKeyboard { NFBRecheckMovieLayout(); }
- (void)closeDesktop { NFBCloseDesktopSplit(); }
- (BOOL)replaceWindowWithDesktop:(UIView *)window { return NFBReplaceSplitWithDesktop(window); }
- (BOOL)desktopActive { return NFBDesktopSplitActive(); }
@end

@interface NFBSplitCoordinator ()
@property(nonatomic,strong) id<NFBSplitBackend> backend;
@property(nonatomic,readwrite) NSUInteger generation;
@property(nonatomic,readwrite) NFBSplitPhase phase;
@property(nonatomic,readwrite) BOOL movieActive;
@property(nonatomic) BOOL enabled, locked, movie, keyboard, updating;
@property(nonatomic,copy) NSString *identity;
@end
@implementation NFBSplitCoordinator
+ (instancetype)shared {
    static NFBSplitCoordinator *instance; static dispatch_once_t once;
    dispatch_once(&once, ^{ instance=[self new]; instance.backend=[NFBOpenSplitBackend new]; });
    return instance;
}
- (void)updateEnabled:(BOOL)enabled locked:(BOOL)locked movie:(BOOL)movie keyboard:(BOOL)keyboard {
    NSAssert(NSThread.isMainThread,@"split coordinator is main-queue only");
    NSString *identity=[self.backend sceneIdentity];
    BOOL changed=self.enabled!=enabled || self.locked!=locked || self.movie!=movie ||
        self.keyboard!=keyboard || ![self.identity isEqualToString:identity];
    self.enabled=enabled; self.locked=locked; self.movie=movie; self.keyboard=keyboard;
    self.identity=identity;
    if (changed) self.generation++;
    // Lock/disable takes precedence, without scheduling any unlock recovery.
    if (!enabled || locked) {
        [self.backend closeDesktop];
        [self.backend applyMovieEnabled:NO];
        self.movieActive=NO;
        self.phase=locked ? NFBSplitPhaseLocked : NFBSplitPhaseDisabled;
    }
}
- (void)reconcile {
    NSAssert(NSThread.isMainThread,@"split coordinator is main-queue only");
    if (self.updating) return;
    self.updating=YES;
    @try {
        if (!self.enabled || self.locked) return;
        self.movieActive=[self.backend applyMovieEnabled:self.movie];
        NFBSplitPhase next=self.movieActive ? ([self.backend desktopActive] ? NFBSplitPhaseMovieDesktop : NFBSplitPhaseMovie) : NFBSplitPhaseNormal;
        if (self.phase!=next) {
            NFBDebugLog(@"split-core: backend=%@ phase=%lu->%lu generation=%lu",self.backend.identifier,
                (unsigned long)self.phase,(unsigned long)next,(unsigned long)self.generation);
            self.phase=next;
        }
    } @finally { self.updating=NO; }
}
- (void)settleMovieKeyboard {
    if (!self.enabled || self.locked || !self.movie || !self.keyboard) return;
    [self.backend settleMovieKeyboard];
}
- (BOOL)replaceWindowWithDesktop:(UIView *)window {
    if (!self.enabled || self.locked || self.updating) return NO;
    self.generation++;
    return [self.backend replaceWindowWithDesktop:window];
}
- (void)closeDesktop { self.generation++; [self.backend closeDesktop]; }
- (BOOL)installBackend:(id<NFBSplitBackend>)backend {
    NSAssert(NSThread.isMainThread,@"split coordinator is main-queue only");
    if (!backend || self.updating || self.movieActive || [self.backend desktopActive] || self.enabled) return NO;
    self.backend=backend; self.identity=nil; self.generation++;
    return YES;
}
@end
