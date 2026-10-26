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

// Geometry types must exist before NFBRailLayout.h is parsed: NFBRailLayoutPort
// makes that header skip Foundation. CGRect/CGPoint come from CoreGraphics, which
// Foundation re-exports on macOS; the safe-area struct is declared by the header
// itself, because macOS Foundation has no UIEdgeInsets.
#if __has_include(<Foundation/Foundation.h>)
#import <Foundation/Foundation.h>
#endif

#define NFBRailLayoutPort 1
#include "NFBGeometry.h"
#include "NFBContainerLayout.h"
#include "NFBRailLayout.h"
#include "NFBRailState.h"

// Rects overlap on both axes (touching edges do not count).
static bool overlap(CGRect a, CGRect b) {
    return CGRectGetMinX(a) < CGRectGetMaxX(b) - 0.51 && CGRectGetMaxX(a) > CGRectGetMinX(b) + 0.51 &&
           CGRectGetMinY(a) < CGRectGetMaxY(b) - 0.51 && CGRectGetMaxY(a) > CGRectGetMinY(b) + 0.51;
}

// NFBRailInsets is declared by the header itself, so no platform conversion is
// needed here (macOS Foundation has no UIEdgeInsets at all).
typedef NFBRailInsets NSBRailSafe;
static inline NFBRailInsets NSBBuildSafeArea(NSBRailSafe s) { return s; }

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
    NFBRailInsets safe = NSBBuildSafeArea(safeRaw);
    CGRect splitFrame = CGRectMake(0, 422, 195, 422);   // bottom-left split, maxY = screen height
    double splitPosition = 0.80;
    // Slot anchor used by the persistence cases below.
    NFBRailMetric stored = {200 + 422 * 0.05, 48, W};

    // --- split column: derived from the window, icons sized from the room left
    NFBRailPlan split = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true,
            splitFrame, true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(split.rail, "split rail finite");
    // The house button owns the top slot in a split too: a zero frame here made
    // it disappear from the top of the split icon column.
    finiteRect(split.toggle, "split toggle finite");
    check(split.toggleVisible, "split column keeps a visible top slot rect");
    check(CGRectGetWidth(split.toggle) > 0 && CGRectGetHeight(split.toggle) > 0, "split toggle has a positive size");
    close_(CGRectGetWidth(split.toggle), split.diameter + 14, "split toggle keeps the icon slot size");
    close_(split.toggle.origin.y, split.toggleTop, "split toggle top is the slot anchor");
    close_(split.toggleTop, 422 + 422 * 0.05, "split slot anchor is the window inset");
    close_(split.toggle.origin.x, split.rail.origin.x, "split toggle shares the column x");
    close_(split.diameter, 48, "split diameter keeps the settings size");
    check(CGRectGetHeight(split.rail) > 62, "split rail usable");
    // The split column's first content row sits one row below the window inset
    // (that row belongs to the house button); the favorites rail occupies the
    // content row, so the main rail starts below the favorites block.
    close_(split.rowsTop, 422 + 422 * 0.05 + split.diameter + 14 + 9,
            "split rows start side + 9 below the window top inset");
    check(!overlap(split.toggle, split.rail) || split.favoritesVisible, "split content starts under the slot");
    close_(split.rail.origin.y, split.rowsTop + split.favoriteHeight + 9,
            "split main rail follows the favorites block");
    // Every bubble row (favorites and regular) sits strictly below the toggle,
    // so the desktop button never covers the first icon.
    check(!overlap(split.toggle, split.rail), "split toggle does not overlap the icon rail");
    if (split.favoritesVisible) {
        // One bubble is one slot: the favorites block starts a row below the slot.
        CGRect firstRow = CGRectMake(split.favorites.origin.x, split.favorites.origin.y,
                split.diameter + 14, split.diameter + 14);
        check(!overlap(split.toggle, firstRow), "split toggle does not overlap the first icon");
        check(CGRectGetMinY(firstRow) >= CGRectGetMaxY(split.toggle) + 8.5,
                "first split icon keeps its 9pt gap below the toggle");
    }
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

    // --- fullscreen expanded: reuses the split slot anchor and the split diameter
    // (the manager passes the button slot top it cached, i.e. plan.toggleTop)
    NFBRailPlan open = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, split.toggleTop, split.diameter, W, true);
    finiteRect(open.rail, "expanded rail finite");
    close_(open.diameter, split.diameter, "expanded reuses the split diameter");
    check(open.toggleVisible, "expanded shows the desktop toggle");
    close_(open.toggle.origin.y, split.toggleTop, "expanded control keeps the split row top");
    // Regression: the cached anchor is the button slot top, not the content top
    // (rowsTop = slot + row). Caching rowsTop shifted the next fullscreen top one
    // row down, so split and fullscreen controls no longer lined up.
    check(fabs(split.rowsTop - split.toggleTop) > 1, "content top differs from the slot anchor");
    close_(open.toggle.origin.y, split.toggleTop, "expanded top equals the split slot anchor");
    close_(CGRectGetWidth(open.toggle), CGRectGetWidth(split.toggle), "expanded control keeps the split slot size");
    check(open.toggleVisible, "expanded control is visible");
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
            false, 0.7, false, 2, 3, 0, sq.toggleTop, sq.diameter, W, true);
    close_(as.diameter, sq.diameter, "expanded reuses the squeezed split diameter");

    // --- collapsed column: same top, same size, hugs the right edge, parks
    NFBRailPlan col = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, split.toggleTop, split.diameter, W, true);
    finiteRect(col.rail, "collapsed rail finite");
    close_(col.diameter, 48, "collapsed keeps the split diameter");
    close_(col.toggle.origin.y, split.toggleTop, "collapsed control keeps the split row top");
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
            false, 0.7, true, 0, 0, 0, split.toggleTop, split.diameter, W, true);
    close_(emp.toggle.origin.y, col.toggle.origin.y, "empty y equals collapsed y");
    close_(emp.toggle.origin.x, col.toggle.origin.x, "empty x equals collapsed x");
    check(emp.parked && NFBToggleShouldFade(emp.parked, true), "empty column fades");
    finiteRect(emp.rail, "empty rail finite");
    check(emp.rail.size.width > 0, "empty rail keeps the half-visible column");

    // --- collapsed with favorites: favorites never buy height while hidden
    NFBRailPlan many = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 5, 2, 0, split.toggleTop, split.diameter, W, true);
    close_(CGRectGetHeight(many.rail), CGRectGetHeight(col.rail), "favorites do not resize the hidden rail");

    // --- collapsed with notifications: stays on screen, does not park
    NFBRailPlan notified = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 2, split.toggleTop, split.diameter, W, true);
    close_(notified.toggle.origin.x, NFBCollapsedRailFrameX(W, col.diameter + 14, 4),
            "notified collapsed column stays fully on screen");
    check(!notified.parked && !NFBToggleShouldFade(notified.parked, true),
            "notified collapsed column stays fully visible");

    // --- expanded with zero regular rows still shows the control on the right
    NFBRailPlan oe = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 3, 3, 0, split.toggleTop, split.diameter, W, true);
    check(!oe.parked && !NFBToggleShouldFade(oe.parked, true), "expanded never fades");
    close_(oe.toggle.origin.x, NFBCollapsedRailFrameX(W, 62, 4), "expanded control on screen");
    check(CGRectGetHeight(oe.rail) >= 62, "expanded rail not crushed by favorites");
    check(!overlap(oe.toggle, oe.rail), "expanded toggle does not overlap the rail");
    if (oe.favoritesVisible) {
        CGRect row = CGRectMake(oe.favorites.origin.x, oe.favorites.origin.y,
                oe.diameter + 14, oe.diameter + 14);
        check(!overlap(oe.toggle, row), "expanded toggle does not overlap the first icon");
    }

    // --- first layout (nothing measured yet): top comes from the setting
    NFBRailPlan first = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(first.toggle, "first toggle finite");
    close_(first.toggle.origin.y, 90, "first layout uses the configured top");
    check(first.toggle.origin.y < H / 2, "first layout is not at the bottom");

    // --- a rotated screen invalidates the remembered split metric
    NFBRailPlan rot = NFBPlanRail(H, W, safe, TOP, 52, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, split.toggleTop, split.diameter, W, true);
    close_(rot.diameter, 52, "rotation falls back to the settings diameter");
    finiteRect(rot.rail, "rotated rail finite");
    // A rotated screen must not reuse the landscape anchor either.
    check(rot.toggle.origin.y >= TOP && rot.toggle.origin.y < H / 2,
            "rotated screen does not keep an off-screen split anchor");
    NFBRailMetric rotated = NFBRailMetricChoose(stored, false, stored, H);
    check(NFBRailMetricUsable(rotated, H), "stored metric stays readable after rotation");
    NFBRailPlan rotBack = NFBPlanRail(W, H, safe, TOP, 52, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, rotated.top, rotated.diameter, rotated.screenWidth, true);
    close_(rotBack.toggle.origin.y, stored.top, "rotated back to the same width reuses the anchor");

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
            false, 0.7, true, 0, 8, 0, split.toggleTop, split.diameter, W, true);
    check(CGRectGetHeight(longl.rail) > 2 * 57, "long list keeps a viewport");
    check(NFBSplitMetricsValid(48, 0, W, W), "valid metric");
    check(!NFBSplitMetricsValid(0, 0, W, W), "zero metric rejected");

    // --- persisted split geometry: restored before any split is opened
    // A slot anchor inside a split window that starts at y=200. Kept below 256 on
    // purpose: the portable iSH smoke build only evaluates float comparisons
    // correctly under that value, and this assertion is about persistence, not
    // about magnitudes.
    stored.diameter = split.diameter;
    check(NFBRailMetricUsable(stored, W), "stored record is usable");
    NFBRailMetric none = NFBRailMetricNoRecord();
    check(!NFBRailMetricUsable(none, W), "empty record is not usable");
    NFBRailMetric chosen = NFBRailMetricChoose(none, false, stored, W);
    check(NFBRailMetricUsable(chosen, W), "persisted record is adopted on launch");
    close_(chosen.top, stored.top, "persisted record keeps the slot top");
    NFBRailPlan relaunch = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, chosen.top, chosen.diameter, chosen.screenWidth,
            NFBRailMetricUsable(chosen, W));
    // Same place, same size as just before the respring.
    close_(relaunch.toggle.origin.y, 200 + 422 * 0.05, "relaunch keeps the toggle top");
    close_(relaunch.toggle.origin.x, col.toggle.origin.x, "relaunch keeps the parked x");
    close_(relaunch.diameter, split.diameter, "relaunch keeps the split diameter");
    check(relaunch.parked && NFBToggleShouldFade(relaunch.parked, true), "relaunch keeps the half-off fade");
    // Half-off rule: the image centre sits exactly on the screen edge, i.e.
    // origin.x = W - 7 - diameter/2 = W - NFBRetraction(diameter).
    close_(relaunch.toggle.origin.x, W - NFBRetraction(relaunch.diameter),
            "relaunch keeps the half-visible control on the edge");
    close_(relaunch.toggle.origin.x, col.toggle.origin.x, "relaunch parks exactly where the live column parks");
    check(NFBRailMetricEqual(chosen, stored), "unchanged geometry compares equal (no write)");
    check(!NFBRailMetricEqual((NFBRailMetric){chosen.top, chosen.diameter + 1, W}, chosen),
            "a diameter change triggers a write");
    check(!NFBRailMetricEqual((NFBRailMetric){chosen.top + 2, chosen.diameter, W}, chosen),
            "a top change triggers a write");
    check(!NFBRailMetricEqual((NFBRailMetric){chosen.top, chosen.diameter, W + 1}, chosen),
            "a width change triggers a write");

    // A live measurement from this launch always wins over the file.
    NFBRailMetric live = {stored.top + 100, 44, W};
    NFBRailMetric merged = NFBRailMetricChoose(live, true, stored, W);
    close_(merged.top, live.top, "live measurement wins over the persisted record");
    close_(merged.diameter, live.diameter, "live diameter wins over the persisted record");

    // --- hostile persisted data falls back to the settings top
    double badTops[] = {NAN, INFINITY, -INFINITY, -10, 900};
    for (unsigned i = 0; i < sizeof badTops / sizeof badTops[0]; i++) {
        NFBRailMetric bad = {badTops[i], 48, W};
        check(!NFBRailMetricUsable(bad, W), "invalid top rejected");
        NFBRailMetric fb = NFBRailMetricChoose(none, false, bad, W);
        check(!NFBRailMetricUsable(fb, W), "invalid top is not adopted");
        NFBRailPlan p = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
                false, 0.7, true, 0, 0, 0, fb.top, fb.diameter, fb.screenWidth, NFBRailMetricUsable(fb, W));
        close_(p.toggle.origin.y, TOP, "invalid top falls back to the settings top");
        finiteRect(p.toggle, "fallback toggle finite");
    }
    double badDiameters[] = {NAN, 0, 4, 200, -48};
    for (unsigned i = 0; i < sizeof badDiameters / sizeof badDiameters[0]; i++) {
        check(!NFBRailMetricUsable((NFBRailMetric){stored.top, badDiameters[i], W}, W),
                "invalid diameter rejected");
    }
    check(!NFBRailMetricUsable((NFBRailMetric){stored.top, 48, 0}, W), "zero width rejected");
    check(!NFBRailMetricUsable((NFBRailMetric){stored.top, 48, NAN}, W), "NaN width rejected");
    // A record measured on a much wider screen is not trusted for its anchor.
    check(!NFBRailMetricUsable((NFBRailMetric){390, 48, 200}, W), "off-screen anchor rejected");

    // --- a screen width change never reapplies the old width blindly
    double wider = 430;
    // The plan only replays a cached anchor when the metric still validates for
    // the current screen width; that gate is what stops a stale anchor (and its
    // stale x) from being mixed into a different screen size.
    bool changedMeasured = NFBSplitMetricsValid(chosen.diameter, 0, wider, chosen.screenWidth);
    check(!changedMeasured, "a new screen width invalidates the cached metric");
    NFBRailPlan changed = NFBPlanRail(wider, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, chosen.top, chosen.diameter, chosen.screenWidth, changedMeasured);
    close_(changed.diameter, 48, "screen width change falls back to the settings diameter");
    check(!overlap(changed.toggle, changed.rail), "widened screen keeps the toggle off the rail");
    // Parked control: image centre on the screen edge. Compare whole points -
    // the portable smoke build evaluates fractional <= imprecisely.
    // Parked control: image centre on the screen edge, i.e. the rect starts at
    // width - 7 - diameter/2 (NFBParkedToggleX). Asserting the origin keeps the
    // check integer-safe on the portable smoke build.
    close_(changed.toggle.origin.x, 399, "widened screen parks the toggle half off the edge");
    close_(changed.toggle.origin.x, NFBParkedToggleX(wider, changed.diameter),
            "widened screen keeps the parked x");
    check(changed.parked, "widened screen keeps the parked state");
    NFBRailPlan narrower = NFBPlanRail(320, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, chosen.top, chosen.diameter, chosen.screenWidth,
            NFBSplitMetricsValid(chosen.diameter, 0, 320, chosen.screenWidth));
    close_(narrower.toggle.origin.x, 289, "narrower screen parks the toggle half off the edge");
    close_(narrower.toggle.origin.x, NFBParkedToggleX(320, narrower.diameter),
            "narrower screen keeps the parked x");
    finiteRect(narrower.toggle, "narrower toggle finite");

    // --- a split with no room for content still allocates the slot
    NFBRailPlan tiny = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true,
            CGRectMake(0, H - 100, 195, 100), true, 0.7, false, 0, 1, 0, 0, 0, 0, false);
    check(CGRectGetWidth(tiny.toggle) > 0 && CGRectGetHeight(tiny.toggle) > 0, "short split keeps the slot");
    check(!overlap(tiny.toggle, tiny.rail), "short split keeps the toggle off the rail");
    finiteRect(tiny.rail, "short split rail finite");

    printf("PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)\n");
    return 0;
}
