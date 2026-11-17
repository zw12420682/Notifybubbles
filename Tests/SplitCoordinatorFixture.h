#import "NFBSplitCoordinator.h"
// Production Open movie routines are not linked into this UIKit-only test.
BOOL NFBUpdateMovieMode(__unused BOOL enabled) { return NO; }
void NFBRecheckMovieLayout(void) {}
@interface SplitBackendFixture : NSObject <NFBSplitBackend>
@property(nonatomic) BOOL active, desktop;
@property(nonatomic) NSUInteger refits, closes, replacements, keyboardChecks, portraitChecks, transitionCancels, windowCloses, fullscreens;
@property(nonatomic,copy) NSString *scene;
@end
@implementation SplitBackendFixture
- (NSString *)identifier { return @"test-engine"; }
- (NSString *)sceneIdentity { return self.scene ?: @"home"; }
- (NFBSplitSnapshot *)captureLayoutInView:(UIView *)root {
    NFBSplitSnapshot *s=[NFBSplitSnapshot new]; s.rootSize=root.bounds.size;
    s.status=NFBSplitSnapshotPresent; s.lowerApp=@"lower";
    s.lowerFrame=CGRectMake(0,151,390,693); return s;
}
- (void)restorePortraitPlacement { self.portraitChecks++; }
- (void)cancelReturnTransition { self.transitionCancels++; }
- (BOOL)closeCurrentWindow { self.windowCloses++; return YES; }
- (BOOL)fullscreenCurrentWindow { self.fullscreens++; return YES; }
- (BOOL)applyMovieEnabled:(BOOL)enabled { self.refits++; return enabled && self.active; }
- (void)settleMovieKeyboard { self.keyboardChecks++; }
- (void)closeDesktop { self.closes++; self.desktop=NO; }
- (BOOL)replaceWindowWithDesktop:(__unused UIView *)window { self.replacements++;self.desktop=YES;return YES; }
- (BOOL)desktopActive { return self.desktop; }
- (NSUInteger)desktopSessionIdentifier { return self.desktop ? 1 : 0; }
- (BOOL)recheckDesktopAfterCleanup:(__unused NSArray<NSString *> *)apps { self.desktop=YES; return YES; }
@end
@interface SplitCoordinatorQueueFixture : NFBSplitCoordinator
@property(nonatomic,strong) NSMutableArray<dispatch_block_t> *checks;
- (void)drainChecks;
@end
@implementation SplitCoordinatorQueueFixture
- (void)enqueueCleanupCheck:(dispatch_block_t)block after:(__unused NSTimeInterval)delay {
    if (!self.checks) self.checks=[NSMutableArray array];
    [self.checks addObject:[block copy]];
}
- (void)enqueueKeyboardCheck:(dispatch_block_t)block after:(NSTimeInterval)delay {
    [self enqueueCleanupCheck:block after:delay];
}
- (void)drainChecks {
    NSArray<dispatch_block_t> *pending=[self.checks copy]; [self.checks removeAllObjects];
    for (dispatch_block_t block in pending) block();
}
@end
static void RunSplitCoordinatorTests(void) {
    SplitCoordinatorQueueFixture *core=[SplitCoordinatorQueueFixture new];
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
    NSUInteger houseGeneration=core.generation, houseCancels=engine.transitionCancels;
    Check([core replaceWindowWithDesktop:nil],@"movie desktop house tap accepted as no-op");
    Check(engine.desktop && engine.replacements==1 && core.generation==houseGeneration &&
        engine.transitionCancels==houseCancels,@"movie desktop single tap preserves session and pending state");
    [core updateEnabled:YES locked:NO movie:NO keyboard:YES];
    Check([core replaceWindowWithDesktop:nil] && engine.replacements==2,@"ordinary mode house retains backend toggle behavior");
    [core updateEnabled:YES locked:NO movie:YES keyboard:YES];
    [core closeDesktop];
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return YES; } refresh:^{}];
    [core drainChecks];
    Check(engine.desktop,@"cleanup schedules desktop through shared core");
    [core closeDesktop];
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return YES; } refresh:^{}];
    [core closeDesktop]; // user command must cancel old queued fallback
    [core drainChecks];
    Check(!engine.desktop,@"user close invalidates delayed desktop fallback");
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return NO; } refresh:^{}];
    [core drainChecks];
    Check(!engine.desktop,@"reopened app guard cancels cleanup fallback");
    NSUInteger generation=core.generation;
    engine.scene=@"new-window";
    [core updateEnabled:YES locked:NO movie:YES keyboard:YES];
    Check(core.generation>generation,@"scene identity invalidates stale generation");
    [core updateEnabled:YES locked:YES movie:YES keyboard:YES];
    NSUInteger checks=engine.keyboardChecks;
    [core settleMovieKeyboard]; [core reconcile];
    Check(!core.movieActive && core.phase==NFBSplitPhaseLocked && !engine.desktop && engine.keyboardChecks==checks,@"lock blocks refit and dismisses desktop");
    [core updateEnabled:YES locked:NO movie:YES keyboard:NO];
    [core schedulePortraitRestoreAfter:0.1]; [core drainChecks];
    Check(engine.portraitChecks==1,@"keyboard dismissal restores through backend");
    [core schedulePortraitRestoreAfter:0.1];
    engine.scene=@"replacement"; [core drainChecks];
    Check(engine.portraitChecks==1,@"stale keyboard callback cannot move new Open window");
    [core updateEnabled:YES locked:NO movie:YES keyboard:YES];
    NSUInteger beforeQueued=engine.keyboardChecks;
    [core scheduleMovieKeyboardChecks];
    engine.desktop=YES; // session changes without changing app/scene identity
    [core drainChecks];
    Check(engine.keyboardChecks==beforeQueued,@"new desktop session rejects old movie keyboard jobs");
    [core closeDesktop];
    [core scheduleMovieKeyboardChecks]; [core drainChecks];
    Check(engine.keyboardChecks==beforeQueued+3,@"same-session movie keyboard jobs run through shared scheduler");
    [core updateEnabled:YES locked:NO movie:YES keyboard:NO];
    NSUInteger beforeRestore=engine.portraitChecks;
    [core schedulePortraitRestoreAfter:0.1];
    [core beginUserWindowOperation]; [core drainChecks];
    Check(engine.portraitChecks==beforeRestore,@"explicit new operation cancels old keyboard restore");
    Check(engine.transitionCancels>0,@"user operation cancels old visual cover");
    Check([core closeCurrentWindow] && engine.windowCloses==1,@"close uses Open backend exactly once");
    Check([core fullscreenCurrentWindow] && engine.fullscreens==1,@"fullscreen uses Open backend exactly once");
    [core scheduleDesktopAfterCleanup:@[@"old"] delay:0 guard:^BOOL { return YES; } refresh:^{}];
    [core beginUserWindowOperation]; [core drainChecks];
    Check(!engine.desktop,@"new explicit operation cancels pending desktop fallback");
    NFBSplitSnapshot *snapshot=[NFBSplitSnapshot new];
    snapshot.status=NFBSplitSnapshotPresent; snapshot.lowerApp=@"lower"; snapshot.rootSize=CGSizeMake(390,844);
    snapshot.lowerFrame=CGRectMake(0,151,390,693);
    Check(![core keyboardRailFitsSnapshot:snapshot],@"full width keyboard hides rail");
    snapshot.lowerFrame=CGRectMake(0,248,335.4,596);
    Check([core keyboardRailFitsSnapshot:snapshot],@"side space permits rail");
    snapshot.status=NFBSplitSnapshotUnknown;
    Check(![core keyboardRailFitsSnapshot:snapshot],@"unknown snapshot cannot reveal rail over keyboard");
    [core updateEnabled:NO locked:NO movie:NO keyboard:NO];
    Check([core installBackend:[SplitBackendFixture new]],@"stopped core permits engine replacement");
}

id<NFBSplitBackend> NFBCreateOpenSplitBackend(void) { return [SplitBackendFixture new]; }
