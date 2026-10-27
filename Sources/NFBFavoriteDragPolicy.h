#pragma once
#include <stdbool.h>

// One clock for a favorite drag.
//
// A held favorite used to be moved twice per frame: every gesture "Changed"
// callback ran the full move (offset, clamp, reorder decision) and a 30 Hz timer
// ran the same function again even when the finger had not moved at all. The
// timer exists for one reason: edge auto-scrolling needs a repeating clock while
// the finger rests inside the edge zone. It now only runs in that case (the
// manager decides with `NFBFavoriteIdleClockActive`), and the move itself is
// skipped when the clock fired for an unchanged finger.
typedef struct {
    bool dragging;             // a favorite is being dragged
    double localY;             // finger position inside the scroll view (content space)
    double viewportHeight;     // scroll view bounds height
    double contentHeight;      // scroll view contentSize height
    double contentOffsetY;     // current offset
    bool fingerMoved;          // the finger moved since the previous move
} NFBFavoriteDragInput;

// Half-open geometry: true when the finger sits in an edge zone that has
// something left to scroll toward. `edge` is the 44pt HIG zone.
static inline bool NFBFavoriteIdleClockActive(NFBFavoriteDragInput in, double edge) {
    if (!in.dragging) return false;
    if (in.contentHeight - in.viewportHeight < 1) return false;   // nothing to scroll
    if (in.localY < edge) return in.contentOffsetY > 0;
    if (in.localY > in.viewportHeight - edge) return in.contentOffsetY < in.contentHeight - in.viewportHeight;
    return false;
}

// Inside an edge zone with something left to scroll, every 30 Hz fire still moves
// the row: there the clock is the only frame source and must keep the exact
// responsiveness. Outside the zones the timer does nothing (the finger callback
// owns the frame), and a moved finger still counts even when the list is already
// at that end.
static inline bool NFBFavoriteEdgeNeedsMove(NFBFavoriteDragInput in) {
    if (!in.dragging) return false;
    double offset = in.contentHeight - in.viewportHeight;
    if (offset < 1) return false;
    if (in.localY < 44.0) return in.contentOffsetY > 0 || in.fingerMoved;
    if (in.localY > in.viewportHeight - 44.0) return in.contentOffsetY < offset || in.fingerMoved;
    return in.fingerMoved;
}
