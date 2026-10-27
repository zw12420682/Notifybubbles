#pragma once
#include <math.h>
#include <stdbool.h>

// Touch policy for the half-hidden column state.
//
// 0.48.82 device report: the collapse control did not respond while a fullscreen
// app was in use. Root cause: the column is moved right so its left half sits past
// the physical screen edge, and a touch only ever arrives inside the screen. A
// point on the *visible* half then falls outside the view's bounds for a view that
// was moved by more than half its width (or a row hanging out of the rail), so
// UIKit's bounds-based -hitTest:withEvent: / -pointInside:withEvent: refused it
// before any gesture saw it. The shared half-hidden helper answers that, and the
// rules are
//   1. a control/row the user can see must be tappable;
//   2. a touch that is not on the visible half must never be stolen from the app
//      underneath (no full-screen invisible capture, no square corners swallowing
//      touches on a circle);
//   3. the minimum comfortable target is 44pt (HIG), which a half circle of a
//      32pt icon (16pt wide) does not reach: the visible half keeps a 22pt radius
//      from its centre so the part on screen is still comfortably tappable. Past
//      the view's own frame edge (or the screen edge) nothing is taken.
//
// 0.48.84 device report: the control still did not respond in desktop or
// fullscreen. Root cause: the visible range was computed as
// `screenWidth - frameOriginX` (the *width* of the on-screen part, ~side/2) and
// then treated as its *left* local edge, so the helper refused every point of the
// real on-screen left half and accepted the half behind the physical edge, which
// no touch can ever reach. `NFBVisibleMaxX` is that same number, now named for
// what it is: the last local x that is on screen. The visible range is always
// [0, maxX] - the view is only ever moved right, never left.

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
