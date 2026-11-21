#pragma once
#include <stdbool.h>
#include <math.h>
// Translation/velocity use the recognizer's native view coordinates (up is -y).
// Begin only for a vertical upward pull; never steal quick-switch/reachability.
static inline bool NFBHomeSwipeCanBegin(double x, double y) {
    return isfinite(x) && isfinite(y) && y < 0 && -y > fabs(x);
}
static inline bool NFBHomeSwipeCanFinish(double x, double y, double vx, double vy) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(vx) || !isfinite(vy)) return false;
    double up = -y;
    if (up < 24 || up <= fabs(x) || vy > 120 || fabs(vx) > fmax(400, fabs(vy))) return false;
    return up >= 64 || vy <= -600;
}
