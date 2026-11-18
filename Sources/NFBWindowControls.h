#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
CGRect NFBSplitFrameInView(UIView *root);
// True when the split framework classes are not resolvable yet (SpringBoard still
// starting): the watcher drops its cached probe and asks again next fire.
BOOL NFBSplitFrameClassUnavailable(void);
void NFBObserveSplitSwitch(NSString *app, BOOL enabled);
void NFBObserveSplitPlacement(NSString *app);
// Re-apply the split placement after the keyboard goes away.
void NFBRecheckSplitPlacement(void);
void NFBResetSplitPlacement(void);

// Layout target only; does not change TrollOpen action or close targets.
NSString *NFBSplitAttachmentApp(void);

// Execute the current window's original TrollOpen right-region single-tap action.
BOOL NFBCloseCurrentSplit(void);
// Close the exact observed landscape window using Open's native close entry.
BOOL NFBCloseObservedLandscape(UIView *window);

// The desktop button attaches only to an expanded portrait window.
UIView *NFBDesktopActionWindow(void);
CGRect NFBWindowFrameInView(UIView *window, UIView *root);

// placement: immediate apply, bounded retries, recheck on keyboard change

// Opt-in layout only; returns YES while a landscape floating scene is visible.
BOOL NFBUpdateMovieMode(BOOL enabled);

CGRect NFBMovieLowerFrameInView(UIView *root);

// Movie-only keyboard settling check, bypassing the 0.2s layout throttle.
void NFBRecheckMovieLayout(void);

// YES stops the bounded post-cleanup checks; NO means old pane is closing or retry is needed.
BOOL NFBRecheckMovieDesktopAfterCleanup(NSArray<NSString *> *clearedApps);

// One main-queue observation used synchronously by Open layout and snapshots.
@interface NFBOpenWindowObservation : NSObject
@property(nonatomic,copy) NSArray<UIView *> *windows, *landscapeWindows;
@property(nonatomic,weak) UIView *portrait;
@property(nonatomic) BOOL classAvailable, sceneAvailable;
@end
NFBOpenWindowObservation *NFBCaptureOpenWindows(void);
BOOL NFBApplyMovieObservation(BOOL enabled, NFBOpenWindowObservation *observation);
