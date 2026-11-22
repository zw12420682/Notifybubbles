#pragma once
#include <stdbool.h>
#include <math.h>
// Translation/velocity use the recognizer's native view coordinates (up is -y).
// Begin only for a vertical upward pull; never steal quick-switch/reachability.
static inline bool NFBHomeSwipeCanBegin(double x, double y) {
    return isfinite(x) && isfinite(y) && y < 0 && -y > fabs(x);
}
// A began sample is not the final direction. Device traces show upward pulls
// beginning with 15pt lateral / 5pt upward motion. On the verified bottom tongue,
// native positive edge motion confirms these small diagonal starts. Completion
// remains vertical-only, so an owned diagonal cannot trigger a close by itself.
static inline bool NFBHomeSwipeCanCapture(double x, double y, double vx, double vy,
    double distance, double velocity) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(vx) || !isfinite(vy) ||
        !isfinite(distance) || !isfinite(velocity)) return false;
    if (NFBHomeSwipeCanBegin(x,y)) return true;
    if (fabs(x)<=1 && fabs(y)<=1)
        return (vy < -20 && -vy > fabs(vx)) ||
            (fabs(vx)<20 && vy<=0 && distance>0 && velocity>0);
    if (y <= -1 && vy <= -10 && distance > 0 && velocity >= 10 &&
        fabs(x) <= 8 && fabs(x) <= 8*(-y)) return true;
    return y < -1 && vy < -20 && distance>0 && velocity>0 &&
        fabs(x)<=24 && fabs(x)<=8*(-y);
}
static inline bool NFBHomeSwipeCanFinish(double x, double y, double vx, double vy) {
    if (!isfinite(x) || !isfinite(y) || !isfinite(vx) || !isfinite(vy)) return false;
    double up = -y;
    if (up < 24 || up <= fabs(x) || vy > 120 || fabs(vx) > fmax(400, fabs(vy))) return false;
    return up >= 40 || vy <= -600;
}
