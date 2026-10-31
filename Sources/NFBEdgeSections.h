#pragma once
#include <math.h>

typedef struct {
    double unreadHeight;
    double backgroundHeight;
    double backgroundOffset;
    double totalHeight;
} NFBEdgeSections;
// Two independent viewports in the column's existing budget, not the screen's
// remaining height. Content overflow scrolls inside its own viewport only.
static inline NFBEdgeSections NFBEdgeSectionLayout(double available, double side,
        double step, unsigned long unread, unsigned long background) {
    NFBEdgeSections p = {0};
    if (!isfinite(available) || !isfinite(side) || !isfinite(step) ||
        available < 0 || side <= 0 || step <= 0) return p;
    double bg = background ? (background - 1) * step + side : 0;
    double uc = unread ? (unread - 1) * step + side : 0;
    double gap = unread && background ? fmin(9, available) : 0;
    double budget = fmax(0, available - gap);
    if (unread && background) {
        p.unreadHeight = fmin(uc, budget / 2);
        p.backgroundHeight = fmin(bg, budget - p.unreadHeight);
        p.unreadHeight = fmin(uc, budget - p.backgroundHeight);
    } else {
        p.unreadHeight = fmin(uc, budget);
        p.backgroundHeight = fmin(bg, budget);
    }
    p.backgroundOffset = p.unreadHeight + gap;
    p.totalHeight = p.backgroundOffset + p.backgroundHeight;
    return p;
}
