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

// Collapsed, non-split column while a fullscreen app is in use. The fullscreen
// app keeps a row even without a notification, and *every* visible image (the
// unread rows, the fullscreen row, the collapse control) shows only its left half
// at alpha 0.5. Nothing stays fully visible and no extra control is added.
static inline bool NFBExpandedAppHalfHidden(bool collapsed, bool split, bool frontAppPresent) {
    return collapsed && !split && frontAppPresent;
}

// --- half-hidden column, screen-space geometry ---------------------------
//
// Goal: in the collapsed fullscreen state every visible image centre sits exactly
// on the screen's right edge, so only the left half of each circle is on screen.
//
// The manager hangs a row (a `side` x `side` bubble) on the *centre* side/2 inside
// the rail, and the icon is inset 7pt; the rail of a collapsed column starts at
// screenWidth - side - margin, so with a 0 origin the icon centre is
//     (screenWidth - side - margin) + side/2 + 7 + diameter/2
//   = screenWidth - margin - diameter/2
// Moving the rail (and the control, a root-view sibling with the shared origin
// NFBPlainRailFrameX) so its frame origin becomes screenWidth - (margin + side/2)
// puts every image centre on the edge, for any diameter and any unread count:
//     origin + 7 + d/2 = (W - (margin + side/2) + margin) + 7 + d/2 = W
// The distance moved is margin + side/2, i.e. the old per-row `diameter/2 - 7`
// (which was 20pt short of the edge for a 48pt icon); only the coordinate it is
// applied in changed: the whole column (rail frame origin and the control frame)
// moves once, and every row keeps the plain side/2 centre. No row carries a second offset and
// no transform is used. Tests/RailLayoutTests.m asserts the screen coordinate for
// 32/44/48/56/80pt plus a squeezed split.
static inline double NFBHalfHiddenShift(double diameter) {
    if (!isfinite(diameter) || diameter <= 0) return 0;
    return 4 + (diameter + 14) / 2;
}

// Origin x of the half-hidden rail and of the collapse control (root sibling).
// The column keeps its width, so the right overhang of the icon image past the
// screen edge is exactly half the diameter and the rail/window ends before the
// hidden right half: only the screen cuts it.
// `margin` is the collapsed column's screen margin (4pt), the one
// NFBCollapsedRailFrameX() subtracts; the same number must be used for both the
// plain and the half-hidden origin, so it is a parameter, not a constant.
static inline double NFBHalfHiddenBubbleOriginX(double screenWidth, double diameter, double margin) {
    if (!isfinite(screenWidth) || !isfinite(diameter) || !isfinite(margin) || diameter <= 0) return 0;
    // Half-hidden keeps the image centre exactly on the edge:
    //   x + side/2 + 7 + d/2 == screenWidth  =>  x = screenWidth - (4 + side/2) + margin
    // The plain column now ends its icon at screenWidth - margin (no 7pt inset), so
    // the plain origin is margin + 7 further left than this formula's base; the
    // shift between the two states is therefore (4 + side/2) - 7.
    return screenWidth - (4 + (diameter + 14) / 2) + margin;
}

// Badge rect inside one icon. The unread count sits inside the icon's own frame
// so it can never spill out of the image (the previous top-right anchor put it
// partly on top of the icon and, on a half-hidden row, over the screen edge).
// `image` is the icon's rect in the bubble's coordinate space (7,7,d,d). The
// width follows the text but is clamped between the pill height and the icon
// diameter, so long counts shrink instead of squashing the icon.
typedef struct { double x, y, width, height; } NFBBadgeRect;
static inline NFBBadgeRect NFBBadgeFrame(double imageX, double imageY, double imageSide,
        double diameter, double textWidth, bool hasText) {
    NFBBadgeRect rect = {imageX, imageY, 0, 0};
    if (!isfinite(imageX) || !isfinite(imageY) || !isfinite(diameter) || diameter <= 0) return rect;
    double side = (isfinite(imageSide) && imageSide > 1) ? imageSide : diameter;
    double height = fmin(20, fmax(14, diameter * 0.42));
    height = fmin(height, side);
    double width = height;
    if (hasText && isfinite(textWidth) && textWidth > 0)
        width = fmax(height, fmin(side, ceil(textWidth) + 10));
    if (width > side) width = side;
    if (width <= 0) width = height;
    double x = imageX + 1, y = imageY + 1;
    if (x + width > imageX + side) x = imageX + side - width;
    if (y + height > imageY + side) y = imageY + side - height;
    if (x < imageX) x = imageX;
    if (y < imageY) y = imageY;
    rect.x = x; rect.y = y; rect.width = width; rect.height = height;
    return rect;
}
static inline bool NFBBadgeInsideImage(NFBBadgeRect badge, double imageX, double imageY, double imageSide) {
    if (!isfinite(badge.width) || !isfinite(badge.height) || badge.width <= 0 || badge.height <= 0) return false;
    return badge.x >= imageX - 0.01 && badge.y >= imageY - 0.01 &&
        badge.x + badge.width <= imageX + imageSide + 0.01 &&
        badge.y + badge.height <= imageY + imageSide + 0.01;
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

// Sane first-use anchor when nothing was ever measured (first launch, no split
// opened yet). The collapsed/expanded column replays the split geometry, so with
// no record at all it must still start at the top - never near the bottom right,
// which is where the fullscreen vertical-position slider used to put the control.
static inline double NFBUnmeasuredColumnTop(double safeTop) {
    if (!isfinite(safeTop) || safeTop < 0) safeTop = 0;
    return fmax(safeTop, 48) + 30;
}

// Collapsed non-split geometry. Only the horizontal placement changes: the
// column hugs the right screen edge. The top must be finite and fully on screen.
static inline double NFBCollapsedRailFrameX(double screenWidth, double railWidth, double margin) {
    if (!isfinite(screenWidth) || !isfinite(railWidth) || !isfinite(margin)) return 0;
    return fmax(0, screenWidth - railWidth - margin);
}
// Fully visible column x. Measured on device: the old `- 7` (the bubble's image
// inset) pushed the expanded column 7pt further from the edge than the split
// column, so the icon overlap did not match. Aligning by the rail edge instead
// puts the icon right edge at screenWidth - margin, the same margin the split
// column keeps from the window gap.
static inline double NFBPlainRailFrameX(double screenWidth, double railWidth, double margin) {
    if (!isfinite(screenWidth) || !isfinite(railWidth) || !isfinite(margin)) return 0;
    return fmax(0, NFBCollapsedRailFrameX(screenWidth, railWidth, margin));
}
// Distance the column moves right when it tucks half off the screen. Derived from
// the two origins above so the two states can never drift apart again.
static inline double NFBColumnHalfHideShift(double screenWidth, double diameter, double margin) {
    double plain = NFBPlainRailFrameX(screenWidth, diameter + 14, margin);
    double hidden = NFBHalfHiddenBubbleOriginX(screenWidth, diameter, margin);
    if (!isfinite(plain) || !isfinite(hidden)) return 0;
    return hidden - plain;
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

// Half-hidden control (collapsed fullscreen column): the zero-notification column
// keeps the control at alpha 0.5 and does not park it any further.
static inline bool NFBToggleShouldFade(bool parked, bool halfHidden) {
    return halfHidden || parked;
}
