#import "NFBSplitCoordinator.h"
#import "NFBWindowControls.h"
#import "NFBDesktopHost.h"
#import "NFBWindowState.h"
#import "NFBTrollOpen.h"
#import "NFBInterfaces.h"
#include <string.h>
@interface NFBOpenSplitBackend : NSObject <NFBSplitBackend>
@property(nonatomic,strong) NFBOpenWindowObservation *layoutObservation;
@end
@implementation NFBOpenSplitBackend
- (NSString *)identifier { return @"open-compat"; }
- (NSString *)sceneIdentity { return [NSString stringWithFormat:@"%@|%p",NFBCurrentWindowState().sceneKey ?: @"unknown",NFBCurrentWindowState().floatingWindow]; }
- (NFBSplitSnapshot *)captureLayoutInView:(UIView *)root {
    NFBSplitSnapshot *snapshot=[NFBSplitSnapshot new];
    snapshot.sceneIdentity=[self sceneIdentity];
    snapshot.lowerApp=NFBSplitAttachmentApp();
    snapshot.lowerWindow=NFBDesktopActionWindow();
    snapshot.lowerFrame=NFBSplitFrameInView(root);
    // reconcile captures once, applies movie and then supplies this same set
    // to the manager's layout capture. No second independent floating scan.
    NFBOpenWindowObservation *observation=self.layoutObservation ?: NFBCaptureOpenWindows();
    self.layoutObservation=nil;
    NSMutableArray<UIView *> *uppers=[NSMutableArray array];
    NSMutableArray<UIWindow *> *hosts=[NSMutableArray array];
    for (UIView *view in observation.landscapeWindows) {
        [uppers addObject:view];
        if (view.window && ![hosts containsObject:view.window]) [hosts addObject:view.window];
    }
    snapshot.upperWindows=uppers; snapshot.upperHostWindows=hosts;
    UIView *upper=uppers.firstObject;
    snapshot.upperWindow=upper;
    snapshot.upperApp=NFBCheckedObject(upper,@"bundleID");
    snapshot.upperLandscape=uppers.count>0;
    snapshot.upperFrame=(upper && root.window) ? [upper convertRect:upper.bounds toView:root] : CGRectNull;
    snapshot.upperStatus=snapshot.upperLandscape ? NFBSplitSnapshotPresent :
        ((!observation.classAvailable || !observation.sceneAvailable) ? NFBSplitSnapshotUnknown : NFBSplitSnapshotAbsent);
    // Object identity only: descriptions include changing frames and would
    // incorrectly invalidate keyboard jobs on every animation frame.
    NSMutableArray<NSString *> *identities=[NSMutableArray array];
    for (UIView *view in uppers) [identities addObject:[NSString stringWithFormat:@"%p|%p",view,view.window]];
    [identities sortUsingSelector:@selector(compare:)];
    snapshot.upperIdentity=[identities componentsJoinedByString:@";"];
    snapshot.rootSize=root.bounds.size;
    snapshot.desktopSessionIdentifier=NFBDesktopSessionIdentifier();
    if (!root.window || !observation.classAvailable || !observation.sceneAvailable)
        snapshot.status=NFBSplitSnapshotUnknown;
    else if (snapshot.lowerApp.length && !CGRectIsNull(snapshot.lowerFrame) && !CGRectIsEmpty(snapshot.lowerFrame))
        snapshot.status=NFBSplitSnapshotPresent;
    else snapshot.status=snapshot.lowerApp.length ? NFBSplitSnapshotUnknown : NFBSplitSnapshotAbsent;
    return snapshot;
}
- (void)restorePortraitPlacement { NFBRecheckSplitPlacement(); }
- (void)cancelReturnTransition { NFBUpdateDesktopReturnTransition(NO); }
- (BOOL)closeCurrentWindow { return NFBCloseCurrentSplit(); }
- (BOOL)fullscreenCurrentWindow { return NFBFullscreenCurrentFloatingWindow(); }
- (BOOL)rotateWindow:(UIView *)window {
    Class cls=NFBTrollFloatingWindowClass();
    if (!NSThread.isMainThread || !cls || ![window isKindOfClass:cls] ||
        !window.window || window.hidden || window.alpha<0.01) return NO;
    if (NFBCheckedBool(window,@"miniWindowModeEnabled",YES) ||
        NFBCheckedBool(window,@"isClosingWithKeepAliveAnimation",YES)) return NO;
    SEL rotate=NSSelectorFromString(@"rotateButtonTapped");
    NSMethodSignature *sig=NFBSignature(window,rotate);
    if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(void))) return NO;
    @try {
        ((void (*)(id,SEL))objc_msgSend)(window,rotate);
        self.layoutObservation=nil; NFBInvalidateWindowState(); return YES;
    } @catch (__unused NSException *error) { return NO; }
}
- (UIView *)upperRotationTarget {
    NFBOpenWindowObservation *observation=NFBCaptureOpenWindows();
    // Multiple upper windows are ambiguous: refuse instead of rotating a random app.
    return observation.landscapeWindows.count==1 ? observation.landscapeWindows.firstObject : nil;
}
- (BOOL)rotateUpperWindow:(UIView *)window {
    if (!window || window!=[self upperRotationTarget]) return NO;
    return [self rotateWindow:window];
}
- (BOOL)applyMovieEnabled:(BOOL)enabled {
    self.layoutObservation=enabled ? NFBCaptureOpenWindows() : nil;
    NFBOpenWindowObservation *captured=self.layoutObservation;
    __weak NFBOpenSplitBackend *weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.layoutObservation==captured) weakSelf.layoutObservation=nil;
    });
    return NFBApplyMovieObservation(enabled,captured);
}
- (void)settleMovieKeyboard { NFBRecheckMovieLayout(); }
- (void)closeDesktop { self.layoutObservation=nil; NFBCloseDesktopSplit(); }
- (BOOL)replaceWindowWithDesktop:(UIView *)window { return NFBReplaceSplitWithDesktop(window); }
- (BOOL)desktopActive { return NFBDesktopSplitActive(); }
- (NSUInteger)desktopSessionIdentifier { return NFBDesktopSessionIdentifier(); }
- (BOOL)recheckDesktopAfterCleanup:(NSArray<NSString *> *)apps { return NFBRecheckMovieDesktopAfterCleanup(apps); }
@end

id<NFBSplitBackend> NFBCreateOpenSplitBackend(void) { return [NFBOpenSplitBackend new]; }
