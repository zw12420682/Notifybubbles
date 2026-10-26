#pragma once
#import <Foundation/Foundation.h>
// The floating-window class. TrollOpen 2.x obfuscates it to TOJBClass012 and no
// longer ships FloatingAppWindow, so resolve across both editions.
Class NFBTrollFloatingWindowClass(void);
// YES means submitted, not yet confirmed visible.
BOOL NFBOpenTrollApp(NSString *bundleID);
BOOL NFBSplitTrollFrontmostApp(void);
NSString *NFBTrollVisibleApp(void);
// Native bridge action with a checked instance-method fallback.
BOOL NFBFullscreenCurrentFloatingWindow(void);
