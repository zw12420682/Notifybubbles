#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
CGRect NFBSplitFrameInView(UIView *root);
BOOL NFBCurrentSplitLandscape(void);
void NFBObserveSplitSwitch(NSString *app, BOOL enabled);
void NFBObserveSplitPlacement(NSString *app);
void NFBResetSplitPlacement(void);

// Layout target only; does not change TrollOpen action or close targets.
NSString *NFBSplitAttachmentApp(void);
