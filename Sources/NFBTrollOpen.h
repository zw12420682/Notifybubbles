#import <Foundation/Foundation.h>

// YES means the request was submitted, not that a window was confirmed visible.
BOOL NFBOpenTrollApp(NSString *bundleID);
BOOL NFBSplitTrollFrontmostApp(void);

NSString *NFBTrollVisibleApp(void);

// Trigger the green bar's tap action (fullscreen the current floating window).
// Returns YES when the bridge accepted the request; a NO means the interface is
// unavailable and the caller should fall back gracefully.
BOOL NFBFullscreenCurrentFloatingWindow(void);

// Toggle the floating window orientation (portrait <-> landscape), matching the
// green bar's long-press "rotate" action. Best-effort: returns YES only when a
// compatible TrollOpen command interface was actually invoked.
BOOL NFBToggleOrientation(void);
