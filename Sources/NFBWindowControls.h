#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
CGRect NFBSplitFrameInView(UIView *root);
// True when the split framework classes are not resolvable yet (SpringBoard still
// starting): the watcher drops its cached probe and asks again next fire.
BOOL NFBSplitFrameClassUnavailable(void);
void NFBObserveSplitSwitch(NSString *app, BOOL enabled);
void NFBObserveSplitPlacement(NSString *app);
void NFBResetSplitPlacement(void);

// Layout target only; does not change TrollOpen action or close targets.
NSString *NFBSplitAttachmentApp(void);

// Execute the current window's original TrollOpen right-region single-tap action.
BOOL NFBCloseCurrentSplit(void);

// The desktop button attaches only to an expanded portrait window.
UIView *NFBDesktopActionWindow(void);
CGRect NFBWindowFrameInView(UIView *window, UIView *root);

