#pragma once
#import <Foundation/Foundation.h>
// YES means submitted, not yet confirmed visible.
BOOL NFBOpenTrollApp(NSString *bundleID);
BOOL NFBSplitTrollFrontmostApp(void);
NSString *NFBTrollVisibleApp(void);
// Native bridge action with a checked instance-method fallback.
BOOL NFBFullscreenCurrentFloatingWindow(void);
