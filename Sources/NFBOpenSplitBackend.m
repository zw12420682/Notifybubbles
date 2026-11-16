#import "NFBSplitCoordinator.h"
#import "NFBWindowControls.h"
#import "NFBDesktopHost.h"
#import "NFBWindowState.h"
#import "NFBTrollOpen.h"
@interface NFBOpenSplitBackend : NSObject <NFBSplitBackend> @end
@implementation NFBOpenSplitBackend
- (NSString *)identifier { return @"open-compat"; }
- (NSString *)sceneIdentity { return [NSString stringWithFormat:@"%@|%p",NFBCurrentWindowState().sceneKey ?: @"unknown",NFBCurrentWindowState().floatingWindow]; }
- (NFBSplitSnapshot *)captureLayoutInView:(UIView *)root {
    NFBSplitSnapshot *snapshot=[NFBSplitSnapshot new];
    snapshot.sceneIdentity=[self sceneIdentity];
    snapshot.lowerApp=NFBSplitAttachmentApp();
    snapshot.lowerWindow=NFBDesktopActionWindow();
    snapshot.lowerFrame=NFBSplitFrameInView(root);
    snapshot.rootSize=root.bounds.size;
    snapshot.desktopSessionIdentifier=NFBDesktopSessionIdentifier();
    BOOL sceneAvailable=NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class] &&
            scene.activationState!=UISceneActivationStateBackground &&
            scene.activationState!=UISceneActivationStateUnattached) sceneAvailable=YES;
    if (!root.window || !NFBTrollFloatingWindowClass() || !sceneAvailable)
        snapshot.status=NFBSplitSnapshotUnknown;
    else if (snapshot.lowerApp.length && !CGRectIsNull(snapshot.lowerFrame) && !CGRectIsEmpty(snapshot.lowerFrame))
        snapshot.status=NFBSplitSnapshotPresent;
    else snapshot.status=snapshot.lowerApp.length ? NFBSplitSnapshotUnknown : NFBSplitSnapshotAbsent;
    return snapshot;
}
- (void)restorePortraitPlacement { NFBRecheckSplitPlacement(); }
- (BOOL)applyMovieEnabled:(BOOL)enabled { return NFBUpdateMovieMode(enabled); }
- (void)settleMovieKeyboard { NFBRecheckMovieLayout(); }
- (void)closeDesktop { NFBCloseDesktopSplit(); }
- (BOOL)replaceWindowWithDesktop:(UIView *)window { return NFBReplaceSplitWithDesktop(window); }
- (BOOL)desktopActive { return NFBDesktopSplitActive(); }
- (NSUInteger)desktopSessionIdentifier { return NFBDesktopSessionIdentifier(); }
- (BOOL)recheckDesktopAfterCleanup:(NSArray<NSString *> *)apps { return NFBRecheckMovieDesktopAfterCleanup(apps); }
@end

id<NFBSplitBackend> NFBCreateOpenSplitBackend(void) { return [NFBOpenSplitBackend new]; }
