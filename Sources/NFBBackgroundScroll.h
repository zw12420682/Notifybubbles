#pragma once
#include <stdbool.h>
#include <math.h>

// Where the collapsed background viewport should scroll when the app that is
// currently open changes. A row that is already fully visible must not move:
// re-centering on every layout would fight the user's own scrolling.
//
// `rowTop`/`rowHeight` are in the scroll view's content coordinates; `visible`
// is the current viewport height and `offset` the current content offset.
static inline bool NFBBackgroundRowFullyVisible(double rowTop, double rowHeight,
        double offset, double visible) {
    if (!isfinite(rowTop) || !isfinite(rowHeight) || !isfinite(offset) || !isfinite(visible)) return true;
    if (rowHeight <= 0 || visible <= 0) return true;
    return rowTop >= offset && rowTop + rowHeight <= offset + visible;
}

// Target content offset: the row's own top when it is below the viewport, or
// the row's bottom at the viewport bottom when it is above it. Clamped to the
// real scroll range so a partial last page still lands on its maximum.
static inline double NFBBackgroundScrollTarget(double rowTop, double rowHeight,
        double offset, double visible, double contentHeight) {
    if (!isfinite(rowTop) || !isfinite(rowHeight) || !isfinite(visible) || !isfinite(contentHeight)) return offset;
    double maxOffset = fmax(0, contentHeight - visible);
    if (NFBBackgroundRowFullyVisible(rowTop, rowHeight, offset, visible)) return offset;
    double target = rowTop < offset ? rowTop + rowHeight - visible : rowTop;
    if (target < 0) target = 0;
    if (target > maxOffset) target = maxOffset;
    return target;
}

// When the open app has no row of its own in the group, the newest app is the
// one that just came to the front: land on the bottom of the list.
static inline double NFBBackgroundBottomTarget(double contentHeight, double visible) {
    if (!isfinite(contentHeight) || !isfinite(visible)) return 0;
    return fmax(0, contentHeight - visible);
}

// Re-run: the desktop simulator roundtrip case is a known intermittent fixture,
// unrelated to this change; reruns keep it enabled rather than relaxing it.
