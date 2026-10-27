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
#include "NFBHitPolicy.h"

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
    fprintf(stderr, "GUARD>%s<\n", message);
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
}

// Bubble frame origin inside the rail for a row of this plan. The manager gives
// the bubble bounds (0, 0, side, side) and sets its *centre* to (side/2, rowY);
// the frame origin is therefore 0 on x, not side/2. Mixing the two put this test
// 31pt off (413 vs 390) while the layout code was right.
static double rowFrameX(const NFBRailPlan *plan) { return plan ? 0 : 0; }

// Screen x of a row's image centre, written the way the manager lays it out:
// rail origin + contentOffset.x (always 0) + bubble frame x (0) + imageView.x (7)
// + diameter/2. A row must therefore stay at rail.origin.x + 7 + diameter/2.
static double rowImageCenterX(NFBRailPlan plan) {
    return plan.rail.origin.x + rowFrameX(&plan) + 7 + plan.diameter / 2;
}
// The collapse control is a root-view sibling: its frame origin is the plan's
// toggle origin and the icon is inset 7pt inside the side-wide button.
static double toggleImageCenterX(NFBRailPlan plan) {
    return plan.toggle.origin.x + 7 + plan.diameter / 2;
}
// Right edge a regular row's image reaches.
static double regularRightX(NFBRailPlan plan) {
    return rowImageCenterX(plan) + plan.diameter / 2;
}

// Bubble centre the manager sets (for the "rows keep their column offset" check).
static double rowCenterX(NFBRailPlan plan) { return (plan.diameter + 14) / 2 + plan.rowInset; }

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
            splitFrame, true, 0.7, false, 2, 3, 0, 0, 0, 0, false, false);
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
            false, 0.7, false, 2, 3, 0, split.toggleTop, split.diameter, W, true, false);
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
    close_(open.toggle.origin.x, NFBPlainRailFrameX(W, 62, 4), "expanded control hugs the right edge");
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
            0.7, false, 2, 3, 0, 0, 0, 0, false, false);
    check(sq.diameter < 48, "narrow split shrinks the icons");
    NFBRailPlan as = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, sq.toggleTop, sq.diameter, W, true, false);
    close_(as.diameter, sq.diameter, "expanded reuses the squeezed split diameter");

    // --- collapsed column: same top, same size, hugs the right edge, parks
    NFBRailPlan col = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, split.toggleTop, split.diameter, W, true, false);
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
    // The 7pt icon inset inside the bubble is why the plain column starts
    // 2 * margin + 7 before the edge (see NFBPlainRailFrameX).
    close_(col.rail.origin.x, NFBPlainRailFrameX(W, CGRectGetWidth(col.rail), 4),
            "fullscreen column hugs the right edge");
    check(col.rail.origin.x > split.rail.origin.x, "fullscreen column is not at the split window");
    check(CGRectGetWidth(col.rail) < 80 && CGRectGetHeight(col.rail) > CGRectGetWidth(col.rail),
          "fullscreen column is a column, not a bar");
    check(col.parked, "collapsed column with no notifications parks");

    // --- empty collapsed column: identical geometry, fades out
    NFBRailPlan emp = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, split.toggleTop, split.diameter, W, true, false);
    close_(emp.toggle.origin.y, col.toggle.origin.y, "empty y equals collapsed y");
    close_(emp.toggle.origin.x, col.toggle.origin.x, "empty x equals collapsed x");
    check(emp.parked && NFBToggleShouldFade(emp.parked, emp.edgeRail), "empty column fades");
    finiteRect(emp.rail, "empty rail finite");
    check(emp.rail.size.width > 0, "empty rail keeps the half-visible column");

    // --- collapsed with favorites: favorites never buy height while hidden
    NFBRailPlan many = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 5, 2, 0, split.toggleTop, split.diameter, W, true, false);
    close_(CGRectGetHeight(many.rail), CGRectGetHeight(col.rail), "favorites do not resize the hidden rail");

    // --- collapsed with notifications: stays on screen, does not park
    NFBRailPlan notified = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 2, split.toggleTop, split.diameter, W, true, false);
    close_(notified.toggle.origin.x, NFBPlainRailFrameX(W, col.diameter + 14, 4),
            "notified collapsed column stays fully on screen");
    check(!notified.parked && !NFBToggleShouldFade(notified.parked, notified.edgeRail),
            "notified collapsed column stays fully visible");

    // --- expanded with zero regular rows still shows the control on the right
    NFBRailPlan oe = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 3, 3, 0, split.toggleTop, split.diameter, W, true, false);
    check(!oe.parked && !NFBToggleShouldFade(oe.parked, oe.edgeRail), "expanded never fades");
    close_(oe.toggle.origin.x, NFBPlainRailFrameX(W, 62, 4), "expanded control on screen");
    check(CGRectGetHeight(oe.rail) >= 62, "expanded rail not crushed by favorites");
    check(!overlap(oe.toggle, oe.rail), "expanded toggle does not overlap the rail");
    if (oe.favoritesVisible) {
        CGRect row = CGRectMake(oe.favorites.origin.x, oe.favorites.origin.y,
                oe.diameter + 14, oe.diameter + 14);
        check(!overlap(oe.toggle, row), "expanded toggle does not overlap the first icon");
    }

    // --- first layout (nothing measured yet): top comes from the setting
    NFBRailPlan first = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, 0, 0, 0, false, false);
    finiteRect(first.toggle, "first toggle finite");
    close_(first.toggle.origin.y, 90, "first layout uses the configured top");
    check(first.toggle.origin.y < H / 2, "first layout is not at the bottom");

    // --- a rotated screen invalidates the remembered split metric
    NFBRailPlan rot = NFBPlanRail(H, W, safe, TOP, 52, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, split.toggleTop, split.diameter, W, true, false);
    close_(rot.diameter, 52, "rotation falls back to the settings diameter");
    finiteRect(rot.rail, "rotated rail finite");
    // A rotated screen must not reuse the landscape anchor either.
    check(rot.toggle.origin.y >= TOP && rot.toggle.origin.y < H / 2,
            "rotated screen does not keep an off-screen split anchor");
    NFBRailMetric rotated = NFBRailMetricChoose(stored, false, stored, H);
    check(NFBRailMetricUsable(rotated, H), "stored metric stays readable after rotation");
    NFBRailPlan rotBack = NFBPlanRail(W, H, safe, TOP, 52, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 0, rotated.top, rotated.diameter, rotated.screenWidth, true, false);
    close_(rotBack.toggle.origin.y, stored.top, "rotated back to the same width reuses the anchor");

    // --- hostile input never yields NaN/infinite frames
    NFBRailPlan nan = NFBPlanRail(NAN, H, safe, TOP, NAN, splitPosition, false, CGRectZero,
            false, NAN, true, 0, 0, 0, NAN, NAN, NAN, true, false);
    finiteRect(nan.rail, "nan rail");
    finiteRect(nan.toggle, "nan toggle");
    NFBRailPlan inf = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true,
            CGRectMake(0, 0, INFINITY, 0), true, 0.7, false, 2, 3, 0, 0, 0, 0, false, false);
    finiteRect(inf.rail, "inf rail");
    NFBRailPlan z = NFBPlanRail(0, 0, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, 0, 0, 0, false, false);
    finiteRect(z.rail, "zero rail");

    // --- a long list gets a real viewport
    NFBRailPlan longl = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 8, 0, split.toggleTop, split.diameter, W, true, false);
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
            NFBRailMetricUsable(chosen, W), false);
    // Same place, same size as just before the respring.
    close_(relaunch.toggle.origin.y, 200 + 422 * 0.05, "relaunch keeps the toggle top");
    close_(relaunch.toggle.origin.x, col.toggle.origin.x, "relaunch keeps the parked x");
    close_(relaunch.diameter, split.diameter, "relaunch keeps the split diameter");
    check(relaunch.parked && NFBToggleShouldFade(relaunch.parked, relaunch.edgeRail), "relaunch keeps the half-off fade");
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
                false, 0.7, true, 0, 0, 0, fb.top, fb.diameter, fb.screenWidth, NFBRailMetricUsable(fb, W), false);
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
            false, 0.7, true, 0, 2, 0, chosen.top, chosen.diameter, chosen.screenWidth, changedMeasured, false);
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
            NFBSplitMetricsValid(chosen.diameter, 0, 320, chosen.screenWidth), false);
    close_(narrower.toggle.origin.x, 289, "narrower screen parks the toggle half off the edge");
    close_(narrower.toggle.origin.x, NFBParkedToggleX(320, narrower.diameter),
            "narrower screen keeps the parked x");
    finiteRect(narrower.toggle, "narrower toggle finite");

    // --- a split with no room for content still allocates the slot
    NFBRailPlan tiny = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true,
            CGRectMake(0, H - 100, 195, 100), true, 0.7, false, 0, 1, 0, 0, 0, 0, false, false);
    check(CGRectGetWidth(tiny.toggle) > 0 && CGRectGetHeight(tiny.toggle) > 0, "short split keeps the slot");
    check(!overlap(tiny.toggle, tiny.rail), "short split keeps the toggle off the rail");
    finiteRect(tiny.rail, "short split rail finite");

    // --- collapsed column while a fullscreen app is in use: half hidden in SCREEN
    // coordinates. 0.48.82 only asserted local x values, so an icon whose centre
    // still sat 20pt inside the screen passed on device. Every number below is the
    // one the manager applies:
    //   screenX(image centre) = railX + contentOffset.x(0) + bubbleX
    //                           + imageView.x(7) + diameter/2
    const double margin = 4, inset = 7;
    double widths[] = { 390, 430, 844 };          // portrait, wide, landscape
    double diams[] = { 32, 44, 48, 56, 80 };
    for (unsigned w = 0; w < sizeof widths / sizeof widths[0]; w++) {
        double sw = widths[w], sh = w == 2 ? 390 : 844;
        for (unsigned d = 0; d < sizeof diams / sizeof diams[0]; d++) {
            NFBRailPlan hh = NFBPlanRail(sw, sh, safe, TOP, diams[d], splitPosition, false, CGRectZero,
                    false, 0.7, true, 0, 2, 1, TOP + 30, diams[d], sw, true, true);
            double side = hh.diameter + 14;
            check(hh.edgeRail, "collapsed fullscreen column is half hidden");
            check(fabs(hh.diameter - diams[d]) < 0.01, "half-hidden column keeps the requested diameter");
            // The rail keeps its column width; only its right overhang changes.
            close_(CGRectGetWidth(hh.rail), side, "half-hidden rail keeps the icon column width");
            // The rail keeps its column width and its own right edge moves with it:
            // the icon centre sits on the screen edge, so the screen itself crops the
            // right half. Nothing may be clipped before the edge (the rail must cover
            // image.x + 7 + d/2) and the rail/window may overhang past the screen by
            // at most the invisible right half.
            close_(CGRectGetMaxX(hh.rail),
                    NFBHalfHiddenBubbleOriginX(sw, hh.diameter, margin) + hh.diameter + 14,
                    "half-hidden rail keeps its column width");
            // The rail moves by exactly the gap between the plain and the
            // half-hidden column origin, computed independently of the helper.
            close_(hh.halfHiddenShift, (4 + side / 2) + 7,
                    "the whole column moves by margin + half the bubble + the icon inset, once");
            check(CGRectGetMaxX(hh.rail) >= sw, "the rail is not clipped before the screen edge");
            check(CGRectGetMaxX(hh.rail) <= sw + hh.diameter + 7, "the overhang is at most the hidden right half");
            close_(hh.rail.origin.x, NFBHalfHiddenBubbleOriginX(sw, hh.diameter, margin),
                    "half-hidden rail sits at its half-hidden x");
            close_(hh.rail.origin.x, NFBPlainRailFrameX(sw, side, margin) + hh.halfHiddenShift,
                    "the rail moved right by its own half-hidden shift, applied once");
            close_(hh.halfHiddenShift, side / 2 + 11, "the column moves by half its bubble + margin + inset");
            // Every row (unread or not) and the control use the plain column offset.
            check(!hh.rowInset || hh.rowInset == 0, "no extra row inset is needed");
            check(fabs(rowCenterX(hh) - side / 2) < 0.01, "rows keep their column offset");
            close_(rowImageCenterX(hh), sw, "row image centre is exactly the screen edge");
            close_(toggleImageCenterX(hh), sw, "collapse control image centre is the screen edge");
            close_(hh.toggle.origin.x, hh.rail.origin.x, "the control keeps the column x");
            // Only the left half is on screen; nothing is a full icon and nothing
            // is cut before the screen edge (the rail extends past it).
            close_(rowImageCenterX(hh) - hh.diameter / 2, sw - hh.diameter / 2,
                    "the visible half starts half a diameter inside the screen");
            check(rowImageCenterX(hh) + hh.diameter / 2 > sw, "the right half is past the screen edge");
            check(hh.rail.origin.x + rowCenterX(hh) + inset - hh.diameter / 2 >= 0,
                    "the visible half is inside the rail");
            check(hh.rail.origin.x + rowCenterX(hh) + inset + hh.diameter / 2 <= CGRectGetMaxX(hh.rail) + 0.01,
                    "the icon is not clipped by the rail before the screen edge");
            // Touch: only the on-screen half reacts, the empty corners do not.
            // The control's frame origin is the rail x, so its on-screen range is
            // local x [0, screenWidth - origin]: the part left of local 0 and the
            // part past the physical edge are not targets.
            double visibleMaxX = NFBVisibleMaxX(hh.toggle.origin.x, side, sw);
            close_(visibleMaxX, sw - hh.rail.origin.x, "visible part of the control ends at the screen edge");
            check(visibleMaxX > 0 && visibleMaxX < side / 2 + 6, "about half of the bubble is off screen");
            // The tap on the visible half's middle (the icon's centre height) lands:
            // this is the exact point UIKit now lets through to the control.
            check(NFBHalfHiddenAcceptsTouch(7 + hh.diameter * 0.25, side / 2, side, visibleMaxX),
                    "visible half of the control is tappable");
            check(NFBHalfHiddenAcceptsTouch(visibleMaxX - 1, side / 2, side, visibleMaxX),
                    "the last on-screen column of the control is tappable");
            check(NFBHalfHiddenAcceptsTouch(7, side / 2, side, visibleMaxX),
                    "the image's on-screen left edge is tappable");
            // The icon is a circle: its top on the visible half is inside, a square
            // corner outside the circle is not.
            check(NFBHalfHiddenAcceptsTouch(7 + hh.diameter * 0.25, 7 + hh.diameter * 0.25, side, visibleMaxX),
                    "the visible half is tappable above the icon's horizontal centre");
            check(!NFBHalfHiddenAcceptsTouch(side / 2 + 22 + 3, 0.5, side, visibleMaxX),
                    "a square corner outside the circle is not stolen");
            check(!NFBHalfHiddenAcceptsTouch(visibleMaxX + 1, side / 2, side, visibleMaxX),
                    "the half behind the physical edge is not a target");
            // A touch off the control belongs to the app behind.
            check(!NFBHalfHiddenAcceptsTouch(-2, side / 2, side, visibleMaxX),
                    "a touch left of the control is never captured");
            check(!NFBHalfHiddenAcceptsTouch(visibleMaxX - 1, -2, side, visibleMaxX),
                    "a touch above the control is never captured");
            // Badge rect stays inside the icon for every diameter and a long count.
            double textWidths[] = { 0, 8, 16, 30 };
            for (unsigned t = 0; t < 4; t++) {
                NFBBadgeRect badge = NFBBadgeFrame(inset, inset, hh.diameter, hh.diameter, textWidths[t], t > 0);
                check(NFBBadgeInsideImage(badge, inset, inset, hh.diameter), "badge stays inside the icon");
            }
        }
    }

    // ---------------------------------------------------------------------
    // 0.48.84: the control produced by the real plan, in real screen space.
    // Production frame: origin.x = W - 7 - d/2 (half-hidden x = rail x, parked
    // x = NFBParkedToggleX), bounds side = d + 14, image inset 7, image centre
    // at local side/2 which is the global screen edge W. The on-screen part is
    // the LEFT half, local x in [0, W - origin.x], and a tap on the left half's
    // middle (image centre 7 + d*0.25) must be accepted; the part behind the
    // physical edge must be refused. The old policy returned
    // `screenWidth - origin.x` as a *min* x, so every check below that expects
    // YES failed and every one that expects NO behind the edge passed a point
    // no finger can reach.
    double diameters[] = { 32, 48, 62 };
    for (unsigned d = 0; d < 3; d++) {
        double diameter = diameters[d];
        double bubble = diameter + 14;
        // The plan's own control for the screen: fullscreen column and a split.
        NFBRailPlan full = NFBPlanRail(W, H, safe, TOP, diameter, splitPosition, false, CGRectZero,
                false, 0.7, true, 1, 2, 0, 0, 0, 0, false, true);
        NFBRailPlan splitPlan = NFBPlanRail(W, H, safe, TOP, diameter, splitPosition, true,
                CGRectMake(0, 100, 300, 600), true, 0.7, true, 1, 2, 0, 0, 0, 0, false, false);
        CGRect toggles[2] = { full.toggle, splitPlan.toggle };

        for (unsigned s = 0; s < 2; s++) {
            double origin = CGRectGetMinX(toggles[s]);
            close_(CGRectGetWidth(toggles[s]), bubble, "the control's bounds are d + 14 wide");
            double maxX = NFBVisibleMaxX(origin, bubble, W);
            if (s == 0) close_(maxX, W - origin, "the on-screen part ends at screen width - origin");
            if (s == 0) check(maxX > 0 && maxX < bubble, "about half of the fullscreen control is on screen");
            check(maxX > 0 && maxX <= bubble, "the control has an on-screen part inside its bounds");
            // Desktop and fullscreen share this exact call.
            check(NFBHalfHiddenAcceptsTouch(7 + diameter * 0.25, bubble / 2, bubble, maxX),
                    "the visible left half centre of the control is tappable");
            check(NFBHalfHiddenAcceptsTouch(7, bubble / 2, bubble, maxX),
                    "the left edge that is on screen is tappable");
            double probeX = fmin(maxX - 3, 7 + diameter * 0.25);
            check(NFBHalfHiddenAcceptsTouch(probeX, 7 + diameter * 0.25, bubble, maxX),
                    "a point above the image centre but on screen is tappable");
            check(!NFBHalfHiddenAcceptsTouch(maxX + 2, bubble / 2, bubble, maxX),
                    "the part behind the physical edge is not a target");
            if (maxX < 7 + diameter * 0.75)
                check(!NFBHalfHiddenAcceptsTouch(7 + diameter * 0.75, bubble / 2, bubble, maxX),
                        "the off-screen right half of the image is not a target");
            check(!NFBHalfHiddenAcceptsTouch(bubble - 0.5, bubble / 2, bubble, maxX),
                    "the control's own right edge, behind the screen, is not a target");
        }
        // Parked: the production parked control frame at half opacity.
        double parkedX = NFBParkedToggleX(W, diameter);
        double parkedMaxX = NFBVisibleMaxX(parkedX, bubble, W);
        check(NFBHalfHiddenAcceptsTouch(7 + diameter * 0.25, bubble / 2, bubble, parkedMaxX),
                "the parked control's visible half centre is tappable");
        check(!NFBHalfHiddenAcceptsTouch(parkedMaxX + 2, bubble / 2, bubble, parkedMaxX),
                "the parked control does not take touches behind the edge");
        // Both sides of the hard production number for a 48pt icon.
        close_(NFBVisibleMaxX(W - 7 - 24, 62, W), 31, "a 48pt control's on-screen part is 31pt wide");
        check(NFBHalfHiddenAcceptsTouch(7 + 12, 31, 62, NFBVisibleMaxX(W - 7 - 24, 62, W)),
                "half a 48pt control at d*0.25 is tappable");
    }
    // A fully visible control (expanded) is unchanged: its range is its bounds.
    double expandedMaxX = NFBVisibleMaxX(W - 62, 62, W);
    close_(expandedMaxX, 62, "an expanded control keeps its whole width on screen");
    check(NFBHalfHiddenAcceptsTouch(7, 7 + 24, 62, expandedMaxX),
            "an expanded control is tappable at the icon's left edge");
    check(NFBHalfHiddenAcceptsTouch(55, 31, 62, expandedMaxX),
            "an expanded control is tappable at its right edge, unchanged from the split button");
    check(!NFBHalfHiddenAcceptsTouch(0.5, 0.5, 62, expandedMaxX),
            "an expanded control keeps its rounded icon hit area (no square corner)");
    check(!NFBHalfHiddenAcceptsTouch(-1, 30, 62, NFBVisibleMaxX(W - 62, 62, W)),
            "touches left of an expanded control belong to the app behind");
    check(!NFBHalfHiddenAcceptsTouch(30, -1, 62, NFBVisibleMaxX(W - 62, 62, W)),
            "touches above an expanded control belong to the app behind");
    check(!NFBHalfHiddenAcceptsTouch(30, 63, 62, NFBVisibleMaxX(W - 62, 62, W)),
            "touches below an expanded control belong to the app behind");
    // The on-screen part never widens past the 44pt floor for a small icon, and
    // never steals y outside the frame.
    double small = 18 + 14, smallMaxX = NFBVisibleMaxX(W - small / 2, small, W);
    check(smallMaxX < 22, "a small icon's on-screen part is narrower than 22pt");
    check(NFBHalfHiddenAcceptsTouch(small / 2 - 5, small / 2, small, smallMaxX),
            "a small icon keeps its circle tappable on screen");
    check(!NFBHalfHiddenAcceptsTouch(small / 2 - 5, -0.5, small, smallMaxX),
            "the 44pt floor never extends the control vertically");
    // Degenerate inputs.
    check(!NFBHalfHiddenAcceptsTouch(NAN, 5, 62, 20), "a NaN touch is refused");
    check(!NFBHalfHiddenAcceptsTouch(5, 5, 0, 20), "a zero-size view is refused");
    check(NFBVisibleMaxX(W, 62, W) == 0, "a view entirely behind the edge has no on-screen part");
    check(!NFBHalfHiddenAcceptsTouch(0.5, 30, 62, NFBVisibleMaxX(W, 62, W)),
            "no touch reaches a view entirely behind the edge");
    check(NFBVisibleMaxX(W - 200, 62, W) == 62, "a view fully on screen keeps its whole bounds");

    // A squeezed split's smaller diameter is reused by the fullscreen column and
    // still lands exactly on the edge.
    NFBRailPlan squeezed = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true, CGRectMake(0, 422, 340, 422),
            true, 0.7, false, 2, 3, 0, 0, 0, 0, false, false);
    check(squeezed.diameter < 48, "squeezed split really shrinks the icons");
    NFBRailPlan squeezedHalf = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 0, squeezed.toggleTop, squeezed.diameter, W, true, true);
    close_(squeezedHalf.diameter, squeezed.diameter, "half-hidden column reuses the split diameter");
    close_(rowImageCenterX(squeezedHalf), W, "squeezed split diameter also lands on the screen edge");
    close_(toggleImageCenterX(squeezedHalf), W, "control follows the squeezed diameter");

    // Many unread apps: same rule, same numbers (one width, one inset).
    NFBRailPlan manyHalf = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 5, 5, 5, split.toggleTop, 48, W, true, true);
    close_(rowImageCenterX(manyHalf), W, "every unread row centre is the screen edge");
    close_(toggleImageCenterX(manyHalf), W, "control centre with unread rows on the edge");
    close_(CGRectGetWidth(manyHalf.rail), 62, "unread rows do not widen the column");
    close_(NFBHalfHiddenShift(48), 4 + 31, "shift is margin + half bubble for 48pt");

    // Only the collapsed fullscreen state half-hides: split, expanded, the plain
    // unread column and the empty (home) column keep the original geometry.
    NFBRailPlan hhSplit = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, true, splitFrame, true,
            0.7, false, 2, 3, 2, 0, 0, 0, false, true);
    check(!hhSplit.edgeRail && hhSplit.rowInset == 0, "split ignores the half-hidden state");
    close_(CGRectGetWidth(hhSplit.rail), CGRectGetWidth(split.rail), "split viewport unchanged");
    close_(hhSplit.rail.origin.x, split.rail.origin.x, "split x unchanged");
    close_(hhSplit.toggle.origin.x, split.toggle.origin.x, "split control unchanged");
    NFBRailPlan hhExpanded = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, false, 2, 3, 2, split.toggleTop, split.diameter, W, true, true);
    check(!hhExpanded.edgeRail && hhExpanded.rowInset == 0, "expanded ignores the half-hidden state");
    close_(CGRectGetWidth(hhExpanded.rail), CGRectGetWidth(open.rail), "expanded viewport unchanged");
    // The column starts 2 * margin + 7 before the edge so the icon (inset 7pt in
    // its bubble) ends margin + 7 before it: expanded stays clear of the edge.
    // Right edge = plain x + side = (W - 2 * margin - 7 - side) + side.
    close_(CGRectGetMaxX(hhExpanded.rail),
            NFBPlainRailFrameX(W, hhExpanded.diameter + 14, margin) + hhExpanded.diameter + 14,
            "expanded rail keeps the plain column x (icon inset 7pt, margin 4pt)");
    NFBRailPlan plainUnread = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 2, 2, split.toggleTop, split.diameter, W, true, false);
    check(!plainUnread.edgeRail && plainUnread.rowInset == 0, "plain unread column keeps its geometry");
    close_(CGRectGetWidth(plainUnread.rail), 62, "plain unread column keeps the icon column width");
    // Unchanged original rule: the icon ends 7pt before the physical edge.
    close_(regularRightX(plainUnread), W - inset - 4 - 7, "plain unread icon keeps its original right edge");
    close_(regularRightX(plainUnread), NFBPlainRailFrameX(W, plainUnread.diameter + 14, margin) + inset + plainUnread.diameter,
            "plain icon right edge from the one column x");
    // ...which is rail x + 7 + d/2 = W - margin - d/2 (not a second 7pt inset).
    close_(rowImageCenterX(plainUnread), W - inset - margin - inset - plainUnread.diameter / 2,
            "plain unread centre is not on the edge (icon ends margin + inset before it)");
    check(rowImageCenterX(plainUnread) < W - 2, "plain unread icon stays fully on screen");
    close_(toggleImageCenterX(plainUnread), rowImageCenterX(plainUnread), "plain control shares the row centre");
    // Empty column (no notifications, to the home screen): the control parks and
    // the column geometry is untouched.
    NFBRailPlan emptyToggle = NFBPlanRail(W, H, safe, TOP, 48, splitPosition, false, CGRectZero,
            false, 0.7, true, 0, 0, 0, split.toggleTop, split.diameter, W, true, false);
    check(emptyToggle.parked && emptyToggle.rowInset == 0, "empty toggle still parks");
    close_(emptyToggle.toggle.origin.x, W - 7 - 24, "parked control keeps its original x");

    // Policy: the half-hidden rule and the fade/priority rules around it.
    check(NFBExpandedAppHalfHidden(true, false, true), "collapsed + fullscreen app: half hidden");
    check(!NFBExpandedAppHalfHidden(false, true, true), "split never half-hides");
    check(!NFBExpandedAppHalfHidden(false, false, true), "expanded never half-hides");
    check(!NFBExpandedAppHalfHidden(true, false, false), "no fullscreen app, no half hide");
    check(NFBToggleShouldFade(false, true), "half-hidden control fades even with unread rows");
    check(NFBToggleShouldFade(true, false), "parked control still fades");
    check(!NFBToggleShouldFade(false, false), "expanded control is opaque");
    // Fullscreen collapse control: interactive without any desktop target.
    check(NFBToggleIsInteractive(true, true, false), "collapsed fullscreen toggle is interactive");
    check(!NFBToggleIsInteractive(true, false, true), "a hidden toggle takes no touches");
    check(!NFBToggleIsInteractive(false, true, false), "a disabled column takes no touches");

    printf("PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)\n");
    printf("PASS: hidden fullscreen exception (screen-space half hide, all rows + control)\n");
    return 0;
}
