#import <Foundation/Foundation.h>
void NFBUpdateOpenEdge(BOOL enabled);
// Split icons suppress visibility; fullscreen apps tuck the native edge button.
// Desktop and visible floating/mini windows keep its swipe-revealed position.
void NFBUpdateOpenEdgeSplitIconsVisible(BOOL visible);
void NFBOpenEdgeAfterClose(void);
