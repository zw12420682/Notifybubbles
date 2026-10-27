#pragma once
#include <math.h>
#include <stdbool.h>
#include <string.h>
#ifndef NFBRailLayoutPort
#import <Foundation/Foundation.h>
#endif
#include "NFBContainerLayout.h"
#include "NFBGeometry.h"
	
// Pure geometry for the notification column. Kept out of the UIKit code so the
// exact regressions (control landing bottom-right, the main rail crushed to a
// hairline, split/fullscreen icons of different size) can be asserted in CI.
// Four insets, field-compatible with UIEdgeInsets but declared here so the header
// builds against Foundation (which has no UIEdgeInsets on macOS) as well as UIKit.
typedef struct { double top, left, bottom, right; } NFBRailInsets;

typedef struct {
    CGRect rail;
    CGRect favorites;
    CGRect toggle;
    double toggleTop;
    double clearCenterY;
    double diameter;
    bool edgeRail;      // collapsed before a fullscreen app: column moved once to its half-hidden x
    double railViewportWidth; // icon column width inside the rail frame (always one bubble wide)
    double rowInset;    // extra x every row adds on top of its column offset (always 0)
    double clearInset;  // same for the clear action (always 0)
    double halfHiddenShift; // how far the rail (and its control) moved right to hug the edge
    double railTop;
    double rowsTop;     // content top, one row below toggleTop
    bool parked;
    bool toggleVisible;
    bool reusedColumn;  // the split column's measured top/size was replayed
    bool measuredColumn; // ...and a measurement actually existed (else the sane top)
    bool favoritesVisible;
    double favoriteHeight;
} NFBRailPlan;

// `split` is the real, resolved split state (an attached floating window with a
// usable frame). Never infer it from the desktop target: the target is nil while
// Open rebuilds its window, which used to make a split look like fullscreen.
//
// Outside a split the column - expanded or collapsed, half hidden or not - is a
// replay of the split column: the top slot that was measured in the split
// (plan.toggleTop, persisted since 0.48.81), the step and the icon diameter the
// split's room allowed. Only the horizontal placement changes (hug the right
// screen edge) and nothing is re-derived from the fullscreen vertical-position
// slider, which used to put the control near the bottom right. With no
// measurement at all the anchor is NFBUnmeasuredColumnTop() (top of the screen),
// never the slider. NFBRailPlan.reusedColumn reports which of the two was used.
// `collapsed` is the column state. `halfHidden` (collapsed && !split && a
// fullscreen app is in use) is the only state that shows just the left half of
// its icons and control; `parked` (collapsed && !split && no notifications, see
// NFBShouldParkToggle below) only moves and fades the control.
//
// Horizontal truth for the half-hidden state: every visible image's centre must be
// exactly the screen width, with only its left half on screen. The rail keeps its
// column width and its x semantics (rows stay at side/2 inside it) and *moves once*
// to NFBHalfHiddenBubbleOriginX() = screenWidth - (margin + side/2); the collapse
// control, a root-view sibling at the rail's x, takes that same frame origin in
// the manager. `halfHiddenShift` is the distance moved and is applied exactly
// once: the plan does not add it to any row inset, and the manager never adds it
// to a row centre (doing both put 0.48.82 rows at screenWidth + shift).
static inline NFBRailPlan NFBPlanRail(double screenWidth, double screenHeight,
        NFBRailInsets safe, double top, double settingsDiameter, double splitPosition,
        bool split, CGRect splitFrame, bool usableSplit, double currentPosition,
        bool collapsed, unsigned long favorites, unsigned long rows, unsigned long notifiedCount,
        double lastSplitTop, double lastSplitDiameter, double lastSplitScreenWidth,
        bool measured, bool halfHidden) {
    NFBRailPlan plan;
    memset(&plan, 0, sizeof(plan));
    plan.rail = CGRectZero;
    plan.railViewportWidth = 0;
    plan.favorites = CGRectZero;
    plan.toggle = CGRectZero;
    if (!isfinite(screenWidth) || !isfinite(screenHeight) || screenWidth <= 0 || screenHeight <= 0) return plan;
    if (!isfinite(settingsDiameter)) settingsDiameter = 48;
    settingsDiameter = fmax(16, fmin(80, settingsDiameter));
    if (!isfinite(top) || top < 0) top = 0;
    // `currentPosition` stays in the signature for the callers' sake, but it no
    // longer places anything: see the anchor comment below.
    (void)currentPosition;
    double splitGap = 4, screenMargin = 4;

    bool reuseSplit = !split && measured &&
        NFBSplitMetricsValid(lastSplitDiameter, 0, screenWidth, lastSplitScreenWidth) &&
        isfinite(lastSplitTop);
    double diameter = reuseSplit ? lastSplitDiameter : settingsDiameter;
    // Expanded and collapsed (split excluded) share one column: same diameter,
    // same step, same top slot. `reuseSplit` decides whether that is the measured
    // split metrics or a plain settings-sized column anchored at the top.
    bool reusedColumn = !split;
    if (split && usableSplit) {
        double room = screenWidth - CGRectGetMaxX(splitFrame) - splitGap - screenMargin;
        if (isfinite(room)) diameter = fmin(diameter, fmax(1, room - 14));
    }
    diameter = fmax(1, diameter);
    double side = diameter + 14;
    double step = diameter + 9;
    double available = fmax(side, screenHeight - top - fmax(safe.bottom, 20) - 20);
    double padding = 12;
    double contentHeight = rows ? (rows - 1) * step + side : 0;
    double height = fmin(available, contentHeight);
    double anchor = top + available * splitPosition;
    // A non-split column never sits above the settings top: both its measured
    // anchor and its unmeasured fallback keep their own sanity ceiling, but the
    // settings top (the slider's upper bound) still applies as the top edge.
    double columnFloor = top;
    double railY = anchor + (step - side / 2) + padding - height;
    railY = fmax(top, fmin(screenHeight - fmax(safe.bottom, 20) - 20 - height, railY));
    // railY is only a split's provisional frame (the split branch below replaces
    // it from the window). A non-split column gets its y from the first row and
    // the content fit further down, so the fullscreen position slider - still
    // received for compatibility - never places it.
    double railWidth = side;
    // Collapsed fullscreen column, half hidden: the column keeps its width, its
    // row budget, its diameter and every row offset; the rail and the collapse
    // control move right together by NFBHalfHiddenShift(), which puts every image
    // centre exactly on the screen's right edge. The rail's own right edge moves
    // with it, so nothing crops the visible half before the screen edge.
    bool edge = halfHidden && collapsed && !split;
    double plainX = NFBPlainRailFrameX(screenWidth, railWidth, screenMargin);
    double railX = edge ? NFBHalfHiddenBubbleOriginX(screenWidth, diameter, screenMargin) : plainX;
    double shift = railX - plainX;
    double frameWidth = railWidth;
    CGRect rail = CGRectMake(railX, railY, frameWidth, height);
    plan.railViewportWidth = railWidth;
    plan.rowInset = 0;
    plan.clearInset = 0;
    plan.halfHiddenShift = shift;
    if (split && usableSplit) {
        double y = fmax(safe.top, CGRectGetMinY(splitFrame));
        double bottom = fmin(screenHeight - safe.bottom, CGRectGetMaxY(splitFrame));
        if (isfinite(y) && isfinite(bottom) && bottom - y >= side) height = fmax(1, bottom - y);
        double x = NFBContainedRailX(CGRectGetMaxX(splitFrame) + splitGap, screenWidth, railWidth, screenMargin);
        if (isfinite(x)) rail = CGRectMake(x, y, railWidth, height);
    }
    plan.clearCenterY = rail.origin.y - 8 - side / 2;

    double ceiling = fmax(safe.top, 12);
    double floorY = screenHeight - fmax(safe.bottom, 12);
    if (split && usableSplit) floorY = fmin(floorY, CGRectGetMaxY(splitFrame) - CGRectGetHeight(splitFrame) * 0.05);
    // The toggle/desktop action always owns the first row - in a split too. The
    // first-row top is therefore allocated here for both modes, before any mode
    // specific branch runs or the row cursor advances. In a split the top comes
    // from the window; outside one it is the remembered split top, so the
    // fullscreen column starts exactly where the split column started instead of
    // being re-derived from the fullscreen position slider (which put it near the
    // bottom right). Whether the slot is actually painted is a separate question
    // (toggleVisible below): in a split it is the desktop button and needs a
    // desktop target, so the manager decides that from the target's availability.
    // Leaving it CGRectZero in a split used to make the desktop button vanish.
    double y;
    if (split && usableSplit) {
        // Original split geometry, untouched: derive the first row from the window
        // even when the result falls below the track's own floor.
        double splitFloor = fmin(floorY, CGRectGetMaxY(splitFrame) - CGRectGetHeight(splitFrame) * 0.05);
        y = fmax(ceiling, fmin(NFBSplitRailTop(CGRectGetMinY(splitFrame), CGRectGetHeight(splitFrame)),
            splitFloor - side - 9));
    } else {
        // Outside a split, start exactly where the split column started. That
        // absolute row is reused as-is; when it would run past the bottom edge,
        // the whole column slides up by just enough to stay on screen (keeping the
        // relative rows, not re-deriving them from the fullscreen slider).
        // Measured slot top, else the sane unmeasured anchor - never the
        // fullscreen position slider.
        // The sane fallback is already clamped against the safe area itself, so
        // the settings top (which may sit above it) only lifts a real
        // measurement.
        double desired;
        if (reuseSplit) {
            desired = isfinite(lastSplitTop) ? fmax(columnFloor, lastSplitTop) : NFBUnmeasuredColumnTop(safe.top);
        } else {
            desired = NFBUnmeasuredColumnTop(safe.top);
        }
        // The existing contract (and the "first layout" assertion) is that with
        // nothing measured the plain settings top still anchors the column; the
        // sane top only guards the case where the settings top itself is absent
        // or higher up than that.
        desired = fmax(desired, top);
        y = fmax(ceiling, desired);
        double lastRowTop = screenHeight - fmax(safe.bottom, 12) - side;
        if (y > lastRowTop) y = fmax(ceiling, lastRowTop);
    }
    // The slot top is the anchor the fullscreen column replays; plan.rowsTop is
    // the content top *after* this row, so the manager must cache this value.
    plan.toggleTop = y;
    plan.toggle = CGRectMake(rail.origin.x, y, side, side);
    // One full step below the slot: a single step put the first icon only 9pt
    // under the button, so their circular images nearly touched/overlapped.
    y += side + 9;
    double room = fmax(0, floorY - y - side - 9);
    // A hidden fullscreen column shows no favorites rail, so favorites must not
    // eat the height budget: doing so crushed the main rail to a hairline.
    bool hideFavorites = !split && collapsed;
    unsigned long favoriteRows = hideFavorites ? 0 : favorites;
    NFBContainerHeights fit = NFBFitContainers(room, side, step, favoriteRows, rows);
    double favoriteHeight = hideFavorites ? 0 : fit.favorites;
    double gap = fit.gap;
    height = fit.regular;
    plan.rail = CGRectMake(rail.origin.x, y + favoriteHeight + gap, frameWidth, height);
    plan.favorites = CGRectMake(rail.origin.x, y, railWidth, favoriteHeight);
    plan.clearCenterY = CGRectGetMaxY(plan.rail) + 9 + side / 2;
    plan.diameter = diameter;
    plan.edgeRail = edge;
    // First content row (favorites block start) - one row below the slot. It is
    // not the slot anchor: feeding it back as lastSplitTop shifted the next
    // fullscreen top down by one row.
    plan.railTop = y;
    plan.rowsTop = y;
    plan.favoritesVisible = favoriteRows > 0 && favoriteHeight > 0;
    plan.favoriteHeight = favoriteHeight;

    plan.toggleVisible = CGRectGetWidth(plan.toggle) > 0;
    plan.reusedColumn = reusedColumn;
    plan.measuredColumn = !split && reuseSplit;
    plan.parked = NFBShouldParkToggle(collapsed, split, notifiedCount);
    // Half-hidden control: a root-view sibling with the same origin as the rail,
    // so it takes the rail's half-hidden x (not `shift` added to a second time).
    // `parked` only fades it; the parked x moved the control right, away from the
    // icon column, which is why it read as a full icon with only its alpha lowered.
    if (edge && plan.toggleVisible) plan.toggle.origin.x = railX;
    else if (plan.parked) {
        double parkedX = NFBParkedToggleX(screenWidth, diameter);
        if (isfinite(parkedX)) plan.toggle.origin.x = parkedX;
    }
    return plan;
}
