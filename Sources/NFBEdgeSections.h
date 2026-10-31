#pragma once
#include <math.h>

typedef struct {
    double unreadHeight;
    double backgroundHeight;
    double backgroundOffset;
    double totalHeight;
} NFBEdgeSections;
// Fixed backgrounds anchor to the bottom of the available area. Adding unread
// rows consumes space above them, never changes the backgrounds' screen y.
static inline NFBEdgeSections NFBEdgeSectionLayout(double available, double side,
        double step, unsigned long unread, unsigned long background) {
    NFBEdgeSections p = {0};
    if (!isfinite(available) || !isfinite(side) || !isfinite(step) ||
        available < 0 || side <= 0 || step <= 0) return p;
    p.backgroundHeight = background ? (background - 1) * step + side : 0;
    double unreadContent = unread ? (unread - 1) * step + side : 0;
    double gap = unread && background ? 9 : 0;
    double remaining = fmax(0, available - p.backgroundHeight - gap);
    p.unreadHeight = fmin(unreadContent, remaining);
    p.backgroundOffset = fmax(0, available - p.backgroundHeight);
    p.totalHeight = available;
    return p;
}
