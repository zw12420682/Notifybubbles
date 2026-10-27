#pragma once
#include <math.h>
#include <stdbool.h>

// Touch policy for the half-hidden column state.
// The visible LEFT half lies inside the view's bounds, local x [0, W-origin].
// UIKit can hit that portion normally; the gesture delegate must not reject it.
// Keep the existing circular radius (22pt floor), clipped to the control bounds
// and physical screen edge, without capturing unrelated app space.
//
// The old helper named W-origin as a minimum and rejected x below it. It was
// actually the visible maximum: rejecting below it discarded the on-screen half.

// 44 / 2: half of the HIG minimum target, used as the radius floor.
#define NFBMinimumTouchRadius 22.0
// How far the icon is inset inside its square bubble.
#define NFBBubbleInset 7.0

// Whether a control may take a touch at `localX/localY` (its own coordinate
// space): on the visible half, inside the square bubble and no further than the
// icon's radius. Outside the square is refused, and so is the part past
// `visibleMaxX` (the part behind the physical screen edge).
static inline bool NFBHalfHiddenAcceptsTouch(double localX, double localY, double side, double visibleMaxX) {
    if (!isfinite(localX) || !isfinite(localY) || !isfinite(side) || !isfinite(visibleMaxX)) return false;
    if (side <= 0 || visibleMaxX <= 0) return false;
    if (localX < 0 || localX > side) return false;
    if (localY < 0 || localY > side) return false;
    if (localX > fmin(visibleMaxX, side)) return false;
    // The radius floor keeps the visible half comfortable (44pt target); a bubble
    // that is mostly past the edge only keeps the part on screen.
    double radius = fmax((side - 2 * NFBBubbleInset) / 2, NFBMinimumTouchRadius);
    double dx = localX - side / 2, dy = localY - side / 2;
    return dx * dx + dy * dy <= radius * radius;
}

// Last local x that is on screen for a view whose frame is `frameOriginX` wide
// `side` inside a window of `screenWidth` (its on-screen width). `side` when the
// whole view is on screen, 0 when it is entirely behind the edge.
static inline double NFBVisibleMaxX(double frameOriginX, double side, double screenWidth) {
    if (!isfinite(frameOriginX) || !isfinite(side) || !isfinite(screenWidth) || side <= 0 || screenWidth <= 0) return 0;
    double maxX = screenWidth - frameOriginX;
    if (maxX < 0) return 0;
    if (maxX > side) return side;
    return maxX;
}

// A collapse/expand cluster is interactive whenever it is on screen, independent
// of whether a desktop target exists: only the split's house button needs one.
static inline bool NFBToggleIsInteractive(bool enabled, bool onScreen, bool hidden) {
    return enabled && onScreen && !hidden;
}
