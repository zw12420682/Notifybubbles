#pragma once
#include <math.h>
static inline double NFBSize(double value) {
    return isfinite(value) ? fmax(32, fmin(80, value)) : 48;
}
static inline double NFBOpacity(double value) {
    return isfinite(value) ? fmax(0.2, fmin(1, value)) : 1;
}
// Expanded image ends 7 points before the physical edge. Move its center
// exactly onto that edge when retracted, exposing half of the circular image.
static inline double NFBRetraction(double diameter) { return diameter / 2 + 7; }

static inline double NFBPosition(double value) { return isfinite(value) ? fmax(0, fmin(1, value)) : 0.7; }
static inline double NFBRowCenter(unsigned long count, unsigned long index, double step, double side) {
    return (count - 1 - index) * step + side / 2;
}
