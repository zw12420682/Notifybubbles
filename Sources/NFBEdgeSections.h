#pragma once
#include <math.h>

// Collapsed edge column viewports. Each area shows as many rows as it has apps,
// up to its cap; beyond the cap it scrolls inside its own clipped viewport.
// Notifications cap at three rows, backgrounds at four.
#define NFBUnreadVisibleRows 3
#define NFBBackgroundVisibleRows 4

typedef struct {
    double unreadHeight;
    double backgroundHeight;
    double backgroundOffset;
    double totalHeight;
} NFBEdgeSections;

// Rows n need (n-1)*step + side, the same rule NFBRowCenter uses.
static inline double NFBEdgeRowsHeight(unsigned long rows, double side, double step) {
    if (rows == 0 || !isfinite(side) || !isfinite(step) || side <= 0 || step <= 0) return 0;
    return (rows - 1) * step + side;
}
// One row for one app, two for two, ... capped at `cap`.
static inline unsigned long NFBEdgeVisibleRows(unsigned long count, unsigned long cap) {
    if (count > cap) return cap;
    return count;
}
// Height of an area that shrinks with its content and only grows to its cap.
static inline double NFBEdgeViewportHeight(unsigned long count, unsigned long cap,
        double side, double step) {
    return NFBEdgeRowsHeight(NFBEdgeVisibleRows(count, cap), side, step);
}

// `available` is the column budget. Each viewport keeps its content height and is
// only clipped when the budget cannot hold both; the notification area yields
// first so the background viewport survives.
static inline NFBEdgeSections NFBEdgeSectionLayout(double available, double side,
        double step, unsigned long unread, unsigned long background) {
    NFBEdgeSections p = {0};
    if (!isfinite(available) || !isfinite(side) || !isfinite(step) ||
        available < 0 || side <= 0 || step <= 0) return p;
    double unreadView = NFBEdgeViewportHeight(unread, NFBUnreadVisibleRows, side, step);
    double backgroundView = NFBEdgeViewportHeight(background, NFBBackgroundVisibleRows, side, step);
    double gap = unread && background ? 9 : 0;
    double budget = fmax(0, available - gap);
    if (unreadView + backgroundView > budget) {
        backgroundView = fmin(backgroundView, budget);
        unreadView = fmax(0, fmin(unreadView, budget - backgroundView));
    }
    p.unreadHeight = unreadView;
    p.backgroundHeight = backgroundView;
    p.backgroundOffset = unreadView + gap;
    p.totalHeight = p.backgroundOffset + backgroundView;
    return p;
}
