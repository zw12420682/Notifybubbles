#import <Foundation/Foundation.h>
void NFBUpdateOpenEdge(BOOL enabled);
// Split icons suppress Open. Scene transitions apply one default presentation:
// fullscreen closes/tucks, other eligible scenes expand the native tray.
// After that, manual collapse and expansion remain under native control.
void NFBUpdateOpenEdgeSplitIconsVisible(BOOL visible);
void NFBOpenEdgeAfterClose(void);
