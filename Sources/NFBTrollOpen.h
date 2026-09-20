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

// Toggle the current floating window orientation (portrait <-> landscape).
// Reads containerOrientation (falling back to sceneOrientation / isLandscape) and
// drives setContainerOrientation: on the floating window instance (TOJBClass012).
// Note: isLandscape does not exist on the 1.5.2 build, so the orientation integer
// is the reliable source of the current state.
BOOL NFBToggleOrientation(void);
