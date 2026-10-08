#import <Foundation/Foundation.h>
void NFBUpdateOpenEdge(BOOL enabled);

// NotifyBubbles' split bubbles visibility. Open's edge icon is hidden only while
// these split icons are actually on screen; every other case (fullscreen app,
// desktop, landscape/mini only, split parked off the corner) falls back to
// Open's own shouldShowEdgeIcon decision.
void NFBUpdateOpenEdgeSplitIconsVisible(BOOL visible);

void NFBOpenEdgeAfterClose(void);
