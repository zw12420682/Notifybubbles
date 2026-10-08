#import <Foundation/Foundation.h>
void NFBUpdateOpenEdge(BOOL enabled);
// Split-icon toggle: YES keeps Open's edge icon suppressed while a split exists.
void NFBUpdateOpenEdgeSplitIcons(BOOL show);

void NFBOpenEdgeAfterClose(void);
void NFBOpenEdgeExpandAfterRotation(void);
// Expand the edge icon into its app list (left-swipe/inward-pan action).
void NFBOpenEdgeExpand(void);
