#import <Foundation/Foundation.h>

// YES means the request was submitted, not that a window was confirmed visible.
BOOL NFBOpenTrollApp(NSString *bundleID);
BOOL NFBSplitTrollFrontmostApp(void);

NSString *NFBTrollVisibleApp(void);

// Close the current floating window. Calls the CLASS method
// +[TOJBBarGestureBridge closeCurrentFloatingWindow] (confirmed by the device-side
// method dump: B16@0:8 on the bridge metaclass). Falls back to the floating
// window's closeWindowWithoutTerminatingProcess* instance helpers.
BOOL NFBCloseCurrentFloatingWindow(void);
