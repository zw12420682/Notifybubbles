#import <Foundation/Foundation.h>

// YES means the request was submitted, not that a window was confirmed visible.
BOOL NFBOpenTrollApp(NSString *bundleID);
BOOL NFBSplitTrollFrontmostApp(void);

NSString *NFBTrollVisibleApp(void);

// Close the current floating window. Calls the floating window's
// closeCurrentFloatingWindow instance method (verified in both 1.3.7 and 1.5.2).
BOOL NFBCloseCurrentFloatingWindow(void);

// Toggle the current floating window orientation (portrait <-> landscape).
// Reads isLandscape and drives setContainerOrientation: on the floating window
// instance (TOJBClass012), the real "rotate" interface behind the green bar's
// long-press action.
BOOL NFBToggleOrientation(void);
