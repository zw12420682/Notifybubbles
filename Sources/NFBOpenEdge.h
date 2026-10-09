#import <Foundation/Foundation.h>
void NFBUpdateOpenEdge(BOOL enabled);
// Split bubbles visible: hide Open edge and tray. Fullscreen app: close tray
// and tuck edge. Other eligible states: expand Open native tray (delete,
// collapse and app icons), matching the supplied screenshot.
void NFBUpdateOpenEdgeSplitIconsVisible(BOOL visible);
void NFBOpenEdgeAfterClose(void);
