#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
CGRect NFBSplitFrameInView(UIView *root);
BOOL NFBCurrentSplitLandscape(void);
void NFBObserveSplitSwitch(NSString *app, BOOL enabled);
void NFBObserveSplitPlacement(NSString *app);
void NFBResetSplitPlacement(void);

// Layout target only; does not change TrollOpen action or close targets.
NSString *NFBSplitAttachmentApp(void);

// Execute the current window's original TrollOpen right-region single-tap action.
BOOL NFBCloseCurrentSplit(void);

// Landscape takes precedence; action always targets the displayed owner window.
UIView *NFBTopActionWindow(void);
BOOL NFBWindowIsLandscape(UIView *window);
CGRect NFBWindowFrameInView(UIView *window, UIView *root);
BOOL NFBPerformTopLongPress(UIView *window);

void NFBObserveRotationLayout(void);
