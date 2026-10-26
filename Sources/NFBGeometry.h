#pragma once
#include <math.h>
static inline double NFBSize(double value) {
    return isfinite(value) ? fmax(32, fmin(80, value)) : 48;
}
static inline double NFBOpacity(double value) {
    return isfinite(value) ? fmax(0.2, fmin(1, value)) : 1;
}
// Expanded image ends 7 points before the physical edge. Move its center
// exactly onto that edge when retracted, exposing half of the circular image.
static inline double NFBRetraction(double diameter) { return diameter / 2 + 7; }

// Collapsed, non-split column while a fullscreen app is in use. That app gets a
// row of its own even without a notification, and it is the only row (plus the
// collapse control) that shows just its left half: those two views move right by
// their own half width until the image centre sits exactly on the screen edge.
// Everything else keeps the original collapsed rule (full icon, original x).
// Both conditions are required, so a split (whose column has the same x) and a
// parked empty column never half-hide anything but the control.
static inline bool NFBExpandedAppHalfHidden(bool collapsed, bool split, bool frontAppPresent) {
    return collapsed && !split && frontAppPresent;
}
// Same x as NFBRetraction puts the expanded image, mirrored: the image is inset 7
// points inside the bubble, so this makes the bubble's image centre equal the
// screen width. Fixed: independent of how many unread icons share the column.
static inline double NFBHalfHiddenBubbleX(double diameter) {
    return isfinite(diameter) ? diameter / 2 - 7 : 0;
}

static inline double NFBPosition(double value) { return isfinite(value) ? fmax(0, fmin(1, value)) : 0.7; }
static inline double NFBRowCenter(unsigned long count, unsigned long index, double step, double side) {
    // count-1-index underflows for an empty list or an out-of-range index and
    // yields ~1.8e19 as a coordinate.
    if (!count || index >= count || !isfinite(step) || !isfinite(side)) return 0;
    return (count - 1 - index) * step + side / 2;
}

// Scroll only as far as necessary; never reorder an active icon to reveal it.
static inline double NFBRevealOffset(double offset, double viewport, double content,
        double rowCenter, double side) {
    double maximum = fmax(0, content - viewport);
    offset = fmax(0, fmin(maximum, offset));
    if (viewport <= 0) return offset;
    double top = rowCenter - side / 2, bottom = rowCenter + side / 2;
    if (side > viewport) offset = rowCenter - viewport / 2;
    else if (top < offset) offset = top;
    else if (bottom > offset + viewport) offset = bottom - viewport;
    return fmax(0, fmin(maximum, offset));
}
static inline double NFBSplitRailTop(double windowTop, double windowHeight) {
    return windowTop + windowHeight * 0.05;
}

// During a split-window transition its reported right edge can briefly leave
// less room than the padded icon strip. Keep the strip inside the screen.
static inline double NFBContainedRailX(double preferred,double viewport,double width,double margin) {
    if (!isfinite(preferred) || !isfinite(viewport) || !isfinite(width) || !isfinite(margin)) return 0;
    return fmax(0,fmin(preferred,fmax(0,viewport-width-margin)));
}

// The collapsed column always reuses the exact geometry of the split column:
// same top edge as the first (desktop button) row and same icon diameter. The
// desktop action sits on the rail's first row, so its top is simply the rail's
// top; replaying the fullscreen position slider there made the control (and the
// parked column) land near the bottom right instead.
static inline double NFBCollapsedRailTop(double splitRailTop) {
    return isfinite(splitRailTop) ? splitRailTop : NAN;
}

// Diameter measured from an actually laid-out split column. A pre-layout
// measurement (transient zero size while windows rebuild) is not usable.
static inline bool NFBSplitMetricsValid(double diameter, double span,
        double screenWidth, double sourceScreenWidth) {
    if (!isfinite(diameter) || !isfinite(span) || !isfinite(screenWidth) || !isfinite(sourceScreenWidth)) return false;
    if (diameter < 16) return false;
    if (span > 0 && span < diameter) return false;
    // A rotated or resized screen changes the space right of the split window.
    if (fabs(screenWidth - sourceScreenWidth) > 1) return false;
    return screenWidth > 0;
}

// Collapsed non-split geometry. Only the horizontal placement changes: the
// column hugs the right screen edge. The top must be finite and fully on screen.
static inline double NFBCollapsedRailFrameX(double screenWidth, double railWidth, double margin) {
    if (!isfinite(screenWidth) || !isfinite(railWidth) || !isfinite(margin)) return 0;
    return fmax(0, screenWidth - railWidth - margin);
}

// Collapsed column that carries a half-hidden row: the viewport widens by one
// bubble so its right edge reaches the physical screen edge. Rows are laid out
// from the view's left edge, so every row (regular ones included) moves together
// and keeps its original x inside the column; only the exception row and the
// toggle add NFBHalfHiddenBubbleX on top. The extra width is plain on-screen
// space (no parent clipping), so the moved views are not cut.
static inline double NFBCollapsedEdgeRailFrameX(double screenWidth, double railWidth, double margin) {
    if (!isfinite(screenWidth) || !isfinite(railWidth) || !isfinite(margin)) return 0;
    return NFBCollapsedRailFrameX(screenWidth, railWidth + margin + 7, margin);
}

// Half-hidden toggle: the image's center belongs exactly on the screen edge, so
// button.origin.x = screenWidth - 7 - diameter/2 (the icon is inset by 7pt).
static inline double NFBParkedToggleX(double screenWidth, double diameter) {
    if (!isfinite(screenWidth) || !isfinite(diameter)) return 0;
    return screenWidth - 7 - diameter / 2;
}

// Only the hidden (collapsed, not split) column parks without notifications.
static inline bool NFBShouldParkToggle(bool collapsed, bool split, unsigned long notifiedCount) {
    return collapsed && !split && notifiedCount == 0;
}

// An expanded column never parks, even when it has nothing to show.
static inline bool NFBToggleShouldFade(bool parked, bool collapsed) {
    return parked && collapsed;
}
