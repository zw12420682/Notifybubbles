// Geometry regression tests for the notification column.
//
// The plan (NFBPlanRail) is the same pure function the manager lays out from, so
// a control drifting to the bottom right, favorites eating the main rail's
// height, a hairline rail, or icons changing size between split and fullscreen
// fails here.
//
// The file is plain C on purpose. CI compiles it with
//   clang -fobjc-arc -framework Foundation -I Sources Tests/RailLayoutTests.m
// and on that SDK Foundation alone does not declare CGRect at all; CoreGraphics
// is pulled in explicitly below (plain structs, no views). UIEdgeInsets is
// likewise only a CoreGraphics struct here; NSBRailSafe mirrors its four fields
// and NSBBuildSafeArea() converts, so the test never needs UIKit.
//
// It also still builds without Foundation, through the portable branch of the
// headers:
//   clang -DNFB_RAIL_PORT=1 -I Sources -I . RailLayoutTests.m -lm -o t
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>

#ifndef NFB_RAIL_PORT
#define NFB_RAIL_PORT 0
#endif

#define NFBRailLayoutPort 1
#include "NFBGeometry.h"
#include "NFBContainerLayout.h"
#include "NFBRailLayout.h"

// Same field order and types as UIEdgeInsets (top, left, bottom, right).
typedef struct { double top, left, bottom, right; } NSBRailSafe;

#ifdef NFBRailLayoutPort
// CGRect/UIEdgeInsets come from CoreGraphics. Foundation on its own re-exports
// them nowhere guaranteed (the CI macOS SDK left CGRect undefined with
// -framework Foundation), so ask for CoreGraphics explicitly - it is a
// framework in its own right and the geometry types are plain structs there,
// which is all this test needs (it never creates a view).
#include <CoreGraphics/CoreGraphics.h>
static inline UIEdgeInsets NSBBuildSafeArea(NSBRailSafe s) {
    UIEdgeInsets i;
    i.top = s.top;
    i.left = s.left;
    i.bottom = s.bottom;
    i.right = s.right;
    return i;
}
#endif

static void check(bool condition, const char *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

static void close_(double a, double b, const char *message) {
    if (!(isfinite(a) && isfinite(b) && fabs(a - b) < 0.51)) {
        fprintf(stderr, "FAIL: %s (%f vs %f)\n", message, a, b);
        exit(1);
    }
}

static void finiteRect(CGRect rect, const char *message) {
    check(isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
          isfinite(rect.size.width) && isfinite(rect.size.height), message);
    check(rect.size.width >= 0 && rect.size.height >= 0, message);
    check(fabs(rect.origin.x) < 10000 && fabs(rect.origin.y) < 10000, message);
}

int main(void) {
    const double W = 390, H = 844, TOP = 90;
    NSBRailSafe safeRaw = { 59, 0, 34, 0 };
    UIEdgeInsets safe = NSBBuildSafeArea(safeRaw);
    CGRect splitFrame = CGRectMake(0, 422, 195, 422);   // bottom-left split, maxY = screen height
    double splitPosition = 0.80;

    // --- split column: derived from the window, icons sized from the room left
    NFBRailPlan split = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true,
            splitFrame, true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(split.rail, "split rail finite");
    finiteRect(split.toggle, "split toggle finite");
    check(!split.toggleVisible, "split column shows no desktop toggle");
    close_(split.diameter, 48, "split diameter keeps the settings size");
    check(CGRectGetHeight(split.rail) > 62, "split rail usable");
    // The split row top is the window inset (5% down the window); the favorites
    // rail occupies that row, so the main rail starts below the favorites block.
    close_(split.rowsTop, 422 + 422 * 0.05, "split rows start at the window top inset");
    close_(split.rail.origin.y, split.rowsTop + split.favoriteHeight + 9,
            "split main rail follows the favorites block");
    check(split.rail.origin.y <= 422 + (844 - 422) - 62, "split rail inside the window");
    check(CGRectGetMaxY(split.rail) <= 844 - 34 + 0.51, "split rail inside the safe area");
    // The split column keeps the split's own right edge (window edge + gap), but
    // is pulled inside the screen when the window leaves too little room:
    // x = min(windowMaxX + 4, screenWidth - railWidth - 4).
    close_(split.rail.origin.x, NFBContainedRailX(CGRectGetMaxX(splitFrame) + 4, W,
            CGRectGetWidth(split.rail), 4), "split rail uses the contained x helper");
    check(CGRectGetMaxX(split.rail) <= W - 4 + 0.51, "split rail stays on screen");
    check(split.favoritesVisible && split.favoriteHeight > 0, "split favorites visible");
    check(!split.parked, "split column never parks");

    // --- fullscreen expanded: reuses the split row and the split diameter
    NFBRailPlan open = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, split.rowsTop, split.diameter, W, true);
    finiteRect(open.rail, "expanded rail finite");
    close_(open.diameter, split.diameter, "expanded reuses the split diameter");
    check(open.toggleVisible, "expanded shows the desktop toggle");
    close_(open.toggle.origin.y, split.rowsTop, "expanded control keeps the split row top");
    close_(open.toggle.origin.x, W - 62 - 4, "expanded control hugs the right edge");
    check(open.rail.origin.y > open.toggle.origin.y, "expanded rail sits below the control");
    check(open.favoritesVisible && open.favoriteHeight > 0, "expanded favorites visible");
    check(!open.parked, "expanded column never parks");
    // The row is inherited from the split (the split window itself sits in the
    // lower half here), so "not at the bottom right" means the control sits on
    // the split row - never on the rail frame derived from the position slider.
    close_(open.toggle.origin.y, splitFrame.origin.y + splitFrame.size.height * 0.05,
            "expanded control is not re-derived from the bottom slider");
    check(open.toggle.origin.y < CGRectGetMaxY(splitFrame) - 62, "expanded control above the window bottom");
    check(CGRectGetWidth(open.rail) > 48, "expanded rail is a column, not a hairline");

    // --- squeezed split (window leaves little room) is reused, not re-measured
    CGRect wide = CGRectMake(0, 422, 340, 422);
    NFBRailPlan sq = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true, wide, true,
            0.7, false, 2, 3, 0, 0, 0, 0, false);
    check(sq.diameter < 48, "narrow split shrinks the icons");
    NFBRailPlan as = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, sq.rowsTop, sq.diameter, W, true);
    close_(as.diameter, sq.diameter, "expanded reuses the squeezed split diameter");

    // --- collapsed column: same top, same size, hugs the right edge, parks
    NFBRailPlan col = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, split.rowsTop, split.diameter, W, true);
    finiteRect(col.rail, "collapsed rail finite");
    close_(col.diameter, 48, "collapsed keeps the split diameter");
    close_(col.toggle.origin.y, split.rowsTop, "collapsed control keeps the split row top");
    close_(col.toggle.origin.y, open.toggle.origin.y, "collapsed y equals expanded y");
    close_(col.toggle.origin.x, W - 7 - 24, "collapsed control parks half off the right edge");
    close_(col.toggle.origin.x, NFBParkedToggleX(W, col.diameter), "parked x helper agrees");
    check(CGRectGetHeight(col.rail) >= 62, "collapsed rail not crushed");
    check(!col.favoritesVisible && col.favoriteHeight == 0, "collapsed hides favorites");
    // Fullscreen (non-split) column hugs the right screen edge, never the split
    // window edge, and it is a vertical column (one icon wide), not a bar.
    close_(col.rail.origin.x, W - CGRectGetWidth(col.rail) - 4, "fullscreen column hugs the right edge");
    check(col.rail.origin.x > split.rail.origin.x, "fullscreen column is not at the split window");
    check(CGRectGetWidth(col.rail) < 80 && CGRectGetHeight(col.rail) > CGRectGetWidth(col.rail),
          "fullscreen column is a column, not a bar");
    check(col.parked, "collapsed column with no notifications parks");

    // --- empty collapsed column: identical geometry, fades out
    NFBRailPlan emp = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, split.rowsTop, split.diameter, W, true);
    close_(emp.toggle.origin.y, col.toggle.origin.y, "empty y equals collapsed y");
    close_(emp.toggle.origin.x, col.toggle.origin.x, "empty x equals collapsed x");
    check(emp.parked && NFBToggleShouldFade(emp.parked, true), "empty column fades");
    finiteRect(emp.rail, "empty rail finite");
    check(emp.rail.size.width > 0, "empty rail keeps the half-visible column");

    // --- collapsed with favorites: favorites never buy height while hidden
    NFBRailPlan many = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 5, 2, 0, split.rowsTop, split.diameter, W, true);
    close_(CGRectGetHeight(many.rail), CGRectGetHeight(col.rail), "favorites do not resize the hidden rail");

    // --- collapsed with notifications: stays on screen, does not park
    NFBRailPlan notified = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 2, split.rowsTop, split.diameter, W, true);
    close_(notified.toggle.origin.x, NFBCollapsedRailFrameX(W, col.diameter + 14, 4),
            "notified collapsed column stays fully on screen");
    check(!notified.parked && !NFBToggleShouldFade(notified.parked, true),
            "notified collapsed column stays fully visible");

    // --- expanded with zero regular rows still shows the control on the right
    NFBRailPlan oe = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 3, 3, 0, split.rowsTop, split.diameter, W, true);
    check(!oe.parked && !NFBToggleShouldFade(oe.parked, true), "expanded never fades");
    close_(oe.toggle.origin.x, NFBCollapsedRailFrameX(W, 62, 4), "expanded control on screen");
    check(CGRectGetHeight(oe.rail) >= 62, "expanded rail not crushed by favorites");

    // --- first layout (nothing measured yet): top comes from the setting
    NFBRailPlan first = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(first.toggle, "first toggle finite");
    close_(first.toggle.origin.y, 90, "first layout uses the configured top");
    check(first.toggle.origin.y < H / 2, "first layout is not at the bottom");

    // --- a rotated screen invalidates the remembered split metric
    NFBRailPlan rot = NFBPlanRail(H, W, safe, TOP, 52, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, split.rowsTop, split.diameter, W, true);
    close_(rot.diameter, 52, "rotation falls back to the settings diameter");
    finiteRect(rot.rail, "rotated rail finite");

    // --- hostile input never yields NaN/infinite frames
    NFBRailPlan nan = NFBPlanRail(NAN, H, safe, TOP, NAN, splitPosition, false, CGRectZero,
            false, NAN, true, 0, 0, 0, NAN, NAN, NAN, true);
    finiteRect(nan.rail, "nan rail");
    finiteRect(nan.toggle, "nan toggle");
    NFBRailPlan inf = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true,
            CGRectMake(0, 0, INFINITY, 0), true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(inf.rail, "inf rail");
    NFBRailPlan z = NFBPlanRail(0, 0, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(z.rail, "zero rail");

    // --- a long list gets a real viewport
    NFBRailPlan longl = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 8, 0, split.rowsTop, split.diameter, W, true);
    check(CGRectGetHeight(longl.rail) > 2 * 57, "long list keeps a viewport");
    check(NFBSplitMetricsValid(48, 0, W, W), "valid metric");
    check(!NFBSplitMetricsValid(0, 0, W, W), "zero metric rejected");

    printf("PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)\n");
    return 0;
}
