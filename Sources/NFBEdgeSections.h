#pragma once
#include <math.h>

// Fixed viewports for the collapsed edge column: the unread area shows three
// rows and the background area shows four, each scrolling inside its own frame.
// Neither viewport may grow with the number of apps, so adding notifications
// can never push the backgrounds around or overlap the area above.
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

// `available` is the column budget. Each viewport keeps its fixed row count and
// is only clipped when the budget cannot hold both; the unread area gives way
// first so the four-row background viewport survives. `unreadContent` is the
// real content height, reported so the caller can size its scroll range.
static inline NFBEdgeSections NFBEdgeSectionLayout(double available, double side,
        double step, unsigned long unread, unsigned long background) {
    NFBEdgeSections p = {0};
    if (!isfinite(available) || !isfinite(side) || !isfinite(step) ||
        available < 0 || side <= 0 || step <= 0) return p;
    double unreadWanted = (unread ? NFBUnreadVisibleRows : 0);
    double backgroundWanted = (background ? NFBBackgroundVisibleRows : 0);
    double unreadView = NFBEdgeRowsHeight((unsigned long)unreadWanted, side, step);
    double backgroundView = NFBEdgeRowsHeight((unsigned long)backgroundWanted, side, step);
    double gap = unread && background ? 9 : 0;
    double budget = fmax(0, available - gap);
    if (unreadView + backgroundView > budget) {
        // Backgrounds keep their viewport; the unread viewport takes the rest.
        backgroundView = fmin(backgroundView, budget);
        unreadView = fmax(0, fmin(unreadView, budget - backgroundView));
    }
    p.unreadHeight = unreadView;
    p.backgroundHeight = backgroundView;
    p.backgroundOffset = unreadView + gap;
    p.totalHeight = p.backgroundOffset + backgroundView;
    return p;
}
