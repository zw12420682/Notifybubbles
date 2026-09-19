#import <Foundation/Foundation.h>

// YES means the request was submitted, not that a window was confirmed visible.
BOOL NFBOpenTrollApp(NSString *bundleID);
BOOL NFBSplitTrollFrontmostApp(void);

NSString *NFBTrollVisibleApp(void);

// Trigger the green bar's tap action (fullscreen the current floating window).
// Returns YES when the bridge accepted the request; a NO means the interface is
// unavailable and the caller should fall back gracefully.
BOOL NFBFullscreenCurrentFloatingWindow(void);
