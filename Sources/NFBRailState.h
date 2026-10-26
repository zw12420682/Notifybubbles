#pragma once
#include <math.h>
#include <stdbool.h>

// Last genuine split column geometry, kept across a SpringBoard relaunch.
//
// Why it exists: the column reuses the split's top edge and icon diameter in
// fullscreen. While running, those numbers live in memory only, so after a
// respring the first fullscreen layout had no measurement and fell back to the
// settings top - the collapse control ended up in the top-right corner until a
// split had been opened once. Persisting the three numbers (button slot top,
// icon diameter, screen width) lets the first layout reproduce the position and
// size the column had before the relaunch.
//
// The record lives in its own preference domain (NFBRailStateStore), never in the
// user's settings domain, so writing it can never touch an option. It stores
// geometry only and every value is validated here before use, so the same header
// runs in the portable (Foundation-free) test build.

typedef struct {
    double top;          // top of the button slot (the column's first row), not the content top
    double diameter;     // icon diameter the split column actually used
    double screenWidth;  // screen width the values were measured on
} NFBRailMetric;

// Ordering helpers. They compare through the sign of a difference rather than a
// bare < / >=, which keeps the result identical on every toolchain this header is
// compiled with (Xcode, CI and the portable iSH smoke test). A NaN difference
// fails isfinite(), so it never counts as a valid bound.
static inline bool NFBLessThan(double value, double bound) {
    double diff = bound - value;
    if (isfinite(diff) && diff > 0) return true;
    return false;
}

static inline bool NFBAtLeast(double value, double bound) {
    double diff = value - bound;
    if (isfinite(diff) && diff >= 0) return true;
    return false;
}

static inline NFBRailMetric NFBRailMetricNoRecord(void) {
    NFBRailMetric empty;
    empty.top = 0;
    empty.diameter = 0;
    empty.screenWidth = 0;
    return empty;
}

// A usable record needs a finite, on-screen slot top and a real icon size on a
// positive-width screen. Anything else is treated as "never measured", so the
// caller falls back to the settings top instead of a garbage anchor.
static inline bool NFBRailMetricUsable(NFBRailMetric metric, double screenWidth) {
    if (!isfinite(metric.top) || !isfinite(metric.diameter) || !isfinite(metric.screenWidth)) return false;
    if (!NFBAtLeast(metric.top, 0)) return false;
    if (!NFBAtLeast(metric.diameter, 16) || !NFBLessThan(metric.diameter, 80.5)) return false;
    if (!NFBAtLeast(metric.screenWidth, 1)) return false;
    if (!NFBLessThan(metric.screenWidth, 100000)) return false;
    // Reject an anchor that cannot sit on the screen it was measured on. The
    // wider of both values is the looser bound, so a record measured in portrait
    // still reads back in landscape on the same device.
    double bound = metric.screenWidth;
    if (isfinite(screenWidth) && NFBLessThan(bound, screenWidth)) bound = screenWidth;
    return NFBLessThan(metric.top, bound);
}

// Chooses the metric to lay out with. `stored` is whatever came from disk;
// `liveMeasured` is true when this launch already measured a split column, in
// which case the live values win over the persisted ones. Returns an unusable
// zero record when neither source is valid.
static inline NFBRailMetric NFBRailMetricChoose(NFBRailMetric live, bool liveMeasured,
        NFBRailMetric stored, double screenWidth) {
    if (liveMeasured && NFBRailMetricUsable(live, screenWidth)) return live;
    if (NFBRailMetricUsable(stored, screenWidth)) return stored;
    return NFBRailMetricNoRecord();
}

// True when two records describe the same geometry, i.e. writing again would be
// a no-op. Used to debounce the on-disk write to real changes only.
static inline bool NFBRailMetricEqual(NFBRailMetric a, NFBRailMetric b) {
    double topGap = a.top - b.top;
    if (topGap < 0) topGap = -topGap;
    double diameterGap = a.diameter - b.diameter;
    if (diameterGap < 0) diameterGap = -diameterGap;
    double widthGap = a.screenWidth - b.screenWidth;
    if (widthGap < 0) widthGap = -widthGap;
    return NFBLessThan(topGap, 0.5) && NFBLessThan(diameterGap, 0.5) && NFBLessThan(widthGap, 0.5);
}
