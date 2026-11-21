#pragma once
#include <stdbool.h>
#include <math.h>
// Translation/velocity use the recognizer's native view coordinates (up is -y).
// Begin only for a vertical upward pull; never steal quick-switch/reachability.
static inline bool NFBHomeSwipeCanBegin(double x, double y) {
    return isfinite(x) && isfinite(y) && y < 0 && -y > fabs(x);
}
// Some system began callbacks reset translation to zero. Use native upward
// distance/velocity only in that ambiguous case; never capture sideways motion.
static inline bool NFBHomeSwipeCanCapture(double x, double y, double vx, double vy,
    double distance, double velocity) {
    if (NFBHomeSwipeCanBegin(x,y)) return true;
    if (!isfinite(x) || !isfinite(y) || !isfinite(vx) || !isfinite(vy) ||
        !isfinite(distance) || !isfinite(velocity) || fabs(x)>1 || fabs(y)>1) return false;
    return (vy < -20 && -vy > fabs(vx)) ||
        (fabs(vx)<20 && vy<=0 && distance>0 && velocity>0);
}
static inline bool NFBHomeSwipeCanFinish(double x, double y, double vx, double vy) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(vx) || !isfinite(vy)) return false;
    double up = -y;
    if (up < 24 || up <= fabs(x) || vy > 120 || fabs(vx) > fmax(400, fabs(vy))) return false;
    return up >= 40 || vy <= -600;
}
