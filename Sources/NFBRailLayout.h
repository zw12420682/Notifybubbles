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
    double clearCenterY;
    double diameter;
    double railTop;
    double rowsTop;
    bool parked;
    bool toggleVisible;
    bool favoritesVisible;
    double favoriteHeight;
} NFBRailPlan;

// `split` is the real, resolved split state (an attached floating window with a
// usable frame). Never infer it from the desktop target: the target is nil while
// Open rebuilds its window, which used to make a split look like fullscreen.
//
// Fullscreen (and the hidden state) reuses the split column: same icon diameter
// as the split measured, and the same absolute row position. Only the horizontal
// placement changes (hug the right screen edge).
static inline NFBRailPlan NFBPlanRail(double screenWidth, double screenHeight,
        NFBRailInsets safe, double top, double settingsDiameter, double splitPosition,
        bool split, CGRect splitFrame, bool usableSplit, double currentPosition,
        bool collapsed, unsigned long favorites, unsigned long rows, unsigned long notifiedCount,
        double lastSplitTop, double lastSplitDiameter, double lastSplitScreenWidth,
        bool measured) {
    NFBRailPlan plan;
    memset(&plan, 0, sizeof(plan));
    plan.rail = CGRectZero;
    plan.favorites = CGRectZero;
    plan.toggle = CGRectZero;
    if (!isfinite(screenWidth) || !isfinite(screenHeight) || screenWidth <= 0 || screenHeight <= 0) return plan;
    if (!isfinite(settingsDiameter)) settingsDiameter = 48;
    settingsDiameter = fmax(16, fmin(80, settingsDiameter));
    if (!isfinite(top) || top < 0) top = 0;
    double splitGap = 4, screenMargin = 4;

    bool reuseSplit = !split && measured &&
        NFBSplitMetricsValid(lastSplitDiameter, 0, screenWidth, lastSplitScreenWidth) &&
        isfinite(lastSplitTop);
    double diameter = reuseSplit ? lastSplitDiameter : settingsDiameter;
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
    double position = isfinite(currentPosition) ? fmax(0, fmin(1, currentPosition)) : 0.7;
    double anchor = top + available * (split ? splitPosition : position);
    double railY = anchor + (step - side / 2) + padding - height;
    railY = fmax(top, fmin(screenHeight - fmax(safe.bottom, 20) - 20 - height, railY));
    double railWidth = side;
    CGRect rail = CGRectMake(NFBCollapsedRailFrameX(screenWidth, railWidth, screenMargin), railY, railWidth, height);
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
    // The toggle/desktop action always owns the first row. In a split the top is
    // derived from the window; outside one it is the remembered split top, so the
    // fullscreen column starts exactly where the split column started instead of
    // being re-derived from the fullscreen position slider (which put it near the
    // bottom right).
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
        double desired = reuseSplit ? lastSplitTop : top;
        if (!isfinite(desired)) desired = top;
        y = fmax(ceiling, desired);
        double lastRowTop = screenHeight - fmax(safe.bottom, 12) - side;
        if (y > lastRowTop) y = fmax(ceiling, lastRowTop);
    }
    bool toggleSlot = !split;
    CGRect toggle = CGRectZero;
    if (toggleSlot) {
        toggle = CGRectMake(rail.origin.x, y, side, side);
        y += side + 9;
    }
    double room = fmax(0, floorY - y - side - 9);
    // A hidden fullscreen column shows no favorites rail, so favorites must not
    // eat the height budget: doing so crushed the main rail to a hairline.
    bool hideFavorites = !split && collapsed;
    unsigned long favoriteRows = hideFavorites ? 0 : favorites;
    NFBContainerHeights fit = NFBFitContainers(room, side, step, favoriteRows, rows);
    double favoriteHeight = hideFavorites ? 0 : fit.favorites;
    double gap = fit.gap;
    height = fit.regular;
    plan.rail = CGRectMake(rail.origin.x, y + favoriteHeight + gap, railWidth, height);
    plan.favorites = CGRectMake(rail.origin.x, y, railWidth, favoriteHeight);
    plan.clearCenterY = CGRectGetMaxY(plan.rail) + 9 + side / 2;
    plan.diameter = diameter;
    plan.railTop = y;
    plan.rowsTop = y;
    plan.favoritesVisible = favoriteRows > 0 && favoriteHeight > 0;
    plan.favoriteHeight = favoriteHeight;

    plan.toggleVisible = toggleSlot;
    plan.toggle = toggle;
    plan.parked = NFBShouldParkToggle(collapsed, split, notifiedCount);
    if (plan.parked) {
        double parkedX = NFBParkedToggleX(screenWidth, diameter);
        if (isfinite(parkedX)) plan.toggle.origin.x = parkedX;
    }
    return plan;
}
