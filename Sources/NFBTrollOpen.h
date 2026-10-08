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

// Shrink the current floating window to its mini size. Like fullscreen, the
// selector's owner drifted between the bridge class and the window instance
// across builds, so both are probed (class method first, then instance).
BOOL NFBMinimizeCurrentFloatingWindow(void);

// Shrink a SPECIFIC floating window (not necessarily the current one) to its
// mini size. Probes the window's own minimize / mini-mode selectors.
BOOL NFBMinimizeFloatingWindow(id window);

// Current visible floating window, or nil when none is present. Returned as an
// opaque object (id) so this header stays UIKit-free and the macOS test target
// can compile it without the iOS SDK.
id NFBCurrentFloatingWindow(void);

// Set the floating window's visual scale (size) and re-sync its container frame,
// preserving the window's center. Returns YES when the scale was submitted.
BOOL NFBSetFloatingVisualScale(double scale);
