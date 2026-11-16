#import "NFBSplitCoordinator.h"
// Production Open movie routines are not linked into this UIKit-only test.
BOOL NFBUpdateMovieMode(__unused BOOL enabled) { return NO; }
void NFBRecheckMovieLayout(void) {}
@interface SplitBackendFixture : NSObject <NFBSplitBackend>
@property(nonatomic) BOOL active, desktop;
@property(nonatomic) NSUInteger refits, closes, replacements, keyboardChecks;
@property(nonatomic,copy) NSString *scene;
@end
@implementation SplitBackendFixture
- (NSString *)identifier { return @"test-engine"; }
- (NSString *)sceneIdentity { return self.scene ?: @"home"; }
- (BOOL)applyMovieEnabled:(BOOL)enabled { self.refits++; return enabled && self.active; }
- (void)settleMovieKeyboard { self.keyboardChecks++; }
- (void)closeDesktop { self.closes++; self.desktop=NO; }
- (BOOL)replaceWindowWithDesktop:(__unused UIView *)window { self.replacements++;self.desktop=YES;return YES; }
- (BOOL)desktopActive { return self.desktop; }
@end
static void RunSplitCoordinatorTests(void) {
    NFBSplitCoordinator *core=[NFBSplitCoordinator new];
    SplitBackendFixture *engine=[SplitBackendFixture new];
    Check([core installBackend:engine],@"core accepts inactive engine without Open calls");
    [core updateEnabled:YES locked:NO movie:NO keyboard:NO]; [core reconcile];
    Check(core.phase==NFBSplitPhaseNormal,@"normal mode phase");
    Check(![core installBackend:[SplitBackendFixture new]],@"cannot swap live engine");
    engine.active=YES;
    [core updateEnabled:YES locked:NO movie:YES keyboard:YES]; [core reconcile];
    Check(core.movieActive && core.phase==NFBSplitPhaseMovie,@"movie uses installed backend");
    [core settleMovieKeyboard]; Check(engine.keyboardChecks==1,@"movie keyboard uses backend");
    [core replaceWindowWithDesktop:nil]; [core reconcile];
    Check(core.phase==NFBSplitPhaseMovieDesktop && engine.replacements==1,@"desktop phase shares core");
    NSUInteger generation=core.generation;
    engine.scene=@"new-window";
    [core updateEnabled:YES locked:NO movie:YES keyboard:YES];
    Check(core.generation>generation,@"scene identity invalidates stale generation");
    [core updateEnabled:YES locked:YES movie:YES keyboard:YES];
    NSUInteger checks=engine.keyboardChecks;
    [core settleMovieKeyboard]; [core reconcile];
    Check(!core.movieActive && core.phase==NFBSplitPhaseLocked && !engine.desktop && engine.keyboardChecks==checks,@"lock blocks refit and dismisses desktop");
    [core updateEnabled:NO locked:NO movie:NO keyboard:NO];
    Check([core installBackend:[SplitBackendFixture new]],@"stopped core permits engine replacement");
}

id<NFBSplitBackend> NFBCreateOpenSplitBackend(void) { return [SplitBackendFixture new]; }
