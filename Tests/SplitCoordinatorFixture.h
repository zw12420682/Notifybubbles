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
- (NSUInteger)desktopSessionIdentifier { return self.desktop ? 1 : 0; }
- (BOOL)recheckDesktopAfterCleanup:(__unused NSArray<NSString *> *)apps { self.desktop=YES; return YES; }
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
    [core closeDesktop];
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return YES; } refresh:^{}];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    Check(engine.desktop,@"cleanup schedules desktop through shared core");
    [core closeDesktop];
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return YES; } refresh:^{}];
    [core closeDesktop]; // user command must cancel old queued fallback
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    Check(!engine.desktop,@"user close invalidates delayed desktop fallback");
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return NO; } refresh:^{}];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    Check(!engine.desktop,@"reopened app guard cancels cleanup fallback");
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
