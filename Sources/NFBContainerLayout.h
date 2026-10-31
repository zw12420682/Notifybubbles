#pragma once
#include <math.h>
#include <stddef.h>
#ifndef NFBRailLayoutPort
#import <Foundation/Foundation.h>
#endif
typedef struct { double favorites; double regular; double gap; } NFBContainerHeights;

static inline double NFBRowFloor(double rows) {
    if (!isfinite(rows) || rows <= 0) return 0;
    return (double)(long long)rows;
}

// Whole rows only, never more than `cap`. A fractional height let the lower
// area's last row hang outside its frame, where the area above painted over it
// (the favorites rail covering the last icon row).
static inline double NFBRowsHeight(double cap, double side, double step) {
    if (!isfinite(cap) || side <= 0 || step <= 0 || cap < side) return 0;
    double rows = 1 + NFBRowFloor((cap - side) / step);
    return side + (rows - 1) * step;
}

// Snap one already-allocated area down to whole rows, keeping at least one row
// when < 0 is never returned. The edge column uses this so its last row can never
// hang outside the frame and be painted over by the area above.
static inline NFBContainerHeights NFBSnapToRows(NFBContainerHeights h, double side, double step) {
    if (step <= 0 || side <= 0) return h;
    double second = NFBRowsHeight(h.regular, side, step);
    if (second == 0 && h.regular > 0 && h.regular >= side) second = side;
    double first = NFBRowsHeight(h.favorites, side, step);
    double budget = h.favorites + h.regular;
    if (first + second > budget) first = NFBRowsHeight(budget - second, side, step);
    if (first + second > budget) second = (h.regular >= side && budget >= side) ? side : 0;
    if (first + second > budget) first = 0;
    return (NFBContainerHeights){ first, second, h.gap };
}

static inline NFBContainerHeights NFBFitContainers(double available, double side, double step, unsigned long favorites, unsigned long regular) {
    // A NaN here propagates to UIView.frame and makes UIKit throw "CALayer bounds
    // contains NaN", which kills SpringBoard. Refuse the layout instead.
    if (!isfinite(available) || !isfinite(side) || !isfinite(step)) return (NFBContainerHeights){0, 0, 0};
    double room = fmax(0, available);
    double a = favorites ? ((favorites - 1) * step + side) : 0;
    double b = regular ? fmin(2 * step + side, (regular - 1) * step + side) : 0;
    double gap = a > 0 && b > 0 ? fmin(9, room) : 0;
    double budget = fmax(0, room - gap);
    // Share the budget as before, then snap each share down to whole rows.
    double first = fmin(a, b > 0 ? budget / 2 : budget);
    double second = fmin(b, fmax(0, budget - first));
    first = fmin(a, fmax(0, budget - second));
    // Whole-row snapping is applied by the caller that needs it (the edge
    // column). A split column sizes itself from the window instead.
    return (NFBContainerHeights){ first, second, gap };
}
