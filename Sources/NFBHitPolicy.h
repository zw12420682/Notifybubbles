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
// before any gesture saw it. Nothing here widens the hit area beyond the visible
// half: the rules are
//   1. a control/row the user can see must be tappable;
//   2. a touch that is not on the visible half must never be stolen from the app
//      underneath (no full-screen invisible capture, no square corners swallowing
//      touches on a circle);
//   3. the minimum comfortable target is 44pt (HIG), which a half circle of a
//      32pt icon (16pt wide) does not reach: the visible half keeps a 22pt radius
//      from its centre so the part on screen is still comfortably tappable.

// 44 / 2: half of the HIG minimum target, used as the radius floor.
#define NFBMinimumTouchRadius 22.0
// How far the icon is inset inside its square bubble.
#define NFBBubbleInset 7.0

// Whether a control may take a touch at `localX/localY` (its own coordinate
// space). `visibleMinX` is the local x where the on-screen part begins; pass 0 for
// a fully visible control. Outside the circle is refused, and so is the part
// before `visibleMinX` (the part past the physical screen edge).
static inline bool NFBHalfHiddenAcceptsTouch(double localX, double localY, double side, double visibleMinX) {
    if (!isfinite(localX) || !isfinite(localY) || !isfinite(side) || !isfinite(visibleMinX)) return false;
    if (side <= 0) return false;
    if (localX < visibleMinX - 0.01) return false;
    double radius = fmax((side - 2 * NFBBubbleInset) / 2, NFBMinimumTouchRadius);
    double dx = localX - side / 2, dy = localY - side / 2;
    if (dx * dx + dy * dy > radius * radius) return false;
    return localY >= 0 && localY <= side;
}

// Local x at which the on-screen part starts for a view whose frame is
// `frameOriginX` wide `side` inside a window of `screenWidth`. 0 when the whole
// view is on screen.
static inline double NFBVisibleMinX(double frameOriginX, double side, double screenWidth) {
    if (!isfinite(frameOriginX) || !isfinite(side) || !isfinite(screenWidth) || side <= 0) return 0;
    double minX = screenWidth - frameOriginX;
    if (minX < 0) return 0;
    if (minX > side) return side;
    return minX;
}

// A collapse/expand cluster is interactive whenever it is on screen, independent
// of whether a desktop target exists: only the split's house button needs one.
static inline bool NFBToggleIsInteractive(bool enabled, bool onScreen, bool hidden) {
    return enabled && onScreen && !hidden;
}
