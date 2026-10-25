#import <Foundation/Foundation.h>
void NFBUpdateOpenEdge(BOOL enabled);
// Split icons suppress Open's edge icon. Scene transitions apply one default presentation:
// fullscreen closes/tucks, other eligible scenes expand the native tray.
// After that, manual collapse and expansion remain under native control.
// The keyboard is not a suppression reason here: it hides these split bubbles,
// which clears the flag below and restores the icon through the native path.
void NFBUpdateOpenEdgeSplitIconsVisible(BOOL visible);
// Same flag, but with a short follow-up pass that re-shows the icon if a native
// refresh hid it while the restore was still animating. Use for restores.
void NFBUpdateOpenEdgeSplitIconsVisibleDeferred(BOOL visible);
void NFBOpenEdgeAfterClose(void);
