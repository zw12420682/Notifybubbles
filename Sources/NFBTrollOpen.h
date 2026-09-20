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

// Expand the current floating window to fullscreen. Historically this moved
// between the bridge class and the floating window instance across builds, and
// the two findings disagree on this firmware, so both are probed: the bridge
// class method first, then the instance method.
BOOL NFBFullscreenCurrentFloatingWindow(void);
