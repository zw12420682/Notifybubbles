#pragma once
#include <math.h>
// Points, not pixels. Invalid settings preserve the original system value.
static inline double NFBKeyboardDockBottom(double original, int enabled, double requested, int portrait) {
    if (!enabled || !portrait || !(original>0) || !isfinite(requested)) return original;
    return fmin(100.0,fmax(0.0,requested));
}
