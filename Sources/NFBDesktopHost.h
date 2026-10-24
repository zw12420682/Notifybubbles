#pragma once
#import <UIKit/UIKit.h>
// Hosts the existing system desktop view; does not create an application scene.
BOOL NFBShowDesktopInSplit(UIView *anchor);
BOOL NFBDesktopSplitActive(void);
void NFBCloseDesktopSplit(void);
void NFBUpdateDesktopSplit(BOOL allowed);

NSString *NFBDesktopSplitError(void);
NSString *NFBConsumeDesktopSplitFailure(void);
