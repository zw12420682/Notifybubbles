#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdbool.h>
#include "CoreGraphics/CoreGraphics.h"
// Objective-C geometry regression test for the notification column.
//
// The block below runs in two places:
//   * CI (macOS): clang -fobjc-arc -framework Foundation -I Sources Tests/RailLayoutTests.m
//   * a plain C port for containers without Foundation:
//       clang -DNFB_RAIL_PORT=1 -I . RailLayoutTests.m -lm && ./a.out
#ifndef NFB_RAIL_PORT
#define NFB_RAIL_PORT 0
#endif
#define NFBRailLayoutPort 1
#include "NFBGeometry.h"
#include "NFBContainerLayout.h"
#include "NFBRailLayout.h"
static void check(bool c, const char *m) { if (c) return; fprintf(stderr, "FAIL: %s\n", m); exit(1); }
__attribute__((unused)) static void close_(double a, double b, const char *m) {
    if (!(isfinite(a) && isfinite(b) && fabs(a - b) < 0.51)) { fprintf(stderr, "FAIL: %s (%f vs %f)\n", m, a, b); exit(1); }
}
__attribute__((unused)) static void finiteRect(CGRect r, const char *m) {
    check(isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height), m);
    check(r.size.width >= 0 && r.size.height >= 0, m);
    check(fabs(r.origin.x) < 10000 && fabs(r.origin.y) < 10000, m);
}
int main(void) {
#if NFB_RAIL_PORT
    const double W = 390, H = 844, TOP = 90;
    UIEdgeInsets safe = UIEdgeInsetsMake(59, 0, 34, 0);
    CGRect splitFrame = CGRectMake(0, 422, 195, 422); // bottom-left: maxY = screen height
    double splitAngle = 0.80;

    NFBRailPlan split = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, true, splitFrame, true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(split.rail, "split rail"); close_(split.diameter, 48, "split diameter");
    finiteRect(split.rail, "split rail"); check(CGRectGetHeight(split.rail) > 62, "split rail usable");
    check(split.favoritesVisible && split.favoriteHeight > 0, "split favorites"); check(!split.parked, "split parks?");
#endif

#if NFB_RAIL_PORT
    NFBRailPlan open = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, false, 2, 3, 0, split.rowsTop, split.diameter, W, true);
    finiteRect(open.rail, "open rail"); close_(open.diameter, split.diameter, "open diameter");
    check(open.toggleVisible, "open toggle"); close_(open.toggle.origin.y, split.rowsTop, "open toggle on split row");
    close_(open.toggle.origin.x, W - 62 - 4, "open toggle x");
    check(open.favoritesVisible && open.favoriteHeight > 0, "open favorites");
    close_(open.toggle.origin.y, split.rowsTop, "expanded control y equals the split row top"); check(open.rail.origin.y > open.toggle.origin.y, "expanded rail below control");
    check(!open.parked, "open parked?");
    CGRect wide = CGRectMake(0, 422, 340, 422);
    NFBRailPlan sq = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, true, wide, true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    check(sq.diameter < 48, "squeeze");
    NFBRailPlan as = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, false, 2, 3, 0, sq.rowsTop, sq.diameter, W, true);
    close_(as.diameter, sq.diameter, "reuse squeezed");
#endif

#if NFB_RAIL_PORT
    NFBRailPlan col = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, true, 0, 2, 0, split.rowsTop, split.diameter, W, true);
    finiteRect(col.rail, "col rail"); close_(col.diameter, 48, "col diameter");
    close_(col.toggle.origin.y, split.rowsTop, "collapsed control y equals the split row top"); check(col.rail.origin.y > col.toggle.origin.y, "collapsed rail below control"); close_(col.toggle.origin.y, open.toggle.origin.y, "col toggle y equals expanded y");
    close_(col.toggle.origin.x, W - 7 - 24, "col toggle x edge center");
    check(CGRectGetHeight(col.rail) >= 62, "col rail crushed");
    check(!col.favoritesVisible && col.favoriteHeight == 0, "fav height"); check(col.parked, "col parked");
#endif

#if NFB_RAIL_PORT
    NFBRailPlan emp = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, true, 0, 0, 0, split.rowsTop, split.diameter, W, true);
    close_(emp.toggle.origin.y, col.toggle.origin.y, "empty y"); close_(emp.toggle.origin.x, col.toggle.origin.x, "empty x");
    check(emp.parked && NFBToggleShouldFade(emp.parked, true), "empty fade");
    NFBRailPlan many = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, true, 5, 2, 0, split.rowsTop, split.diameter, W, true);
    close_(CGRectGetHeight(many.rail), CGRectGetHeight(col.rail), "fav count height");
#endif

#if NFB_RAIL_PORT
    NFBRailPlan oe = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, false, 3, 3, 0, split.rowsTop, split.diameter, W, true);
    check(!oe.parked && !NFBToggleShouldFade(oe.parked, true), "expanded empty fade");
    close_(oe.toggle.origin.x, NFBCollapsedRailFrameX(W, 62, 4), "expanded onscreen");
#endif

#if NFB_RAIL_PORT
    NFBRailPlan first = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(first.toggle, "default"); close_(first.toggle.origin.y, 90, "default top");
    check(first.toggle.origin.y < H / 2, "not bottom");
    NFBRailPlan rot = NFBPlanRail(H, W, safe, TOP, 52, splitAngle, false, CGRectZero, false, 0.7, false, 2, 3, 0, split.rowsTop, split.diameter, W, true);
    close_(rot.diameter, 52, "rotation invalidates"); finiteRect(rot.rail, "rot rail");
    NFBRailPlan nan = NFBPlanRail(NAN, H, safe, TOP, NAN, splitAngle, false, CGRectZero, false, NAN, true, 0, 0, 0, NAN, NAN, NAN, true);
    finiteRect(nan.rail, "nan rail"); finiteRect(nan.toggle, "nan toggle");
    NFBRailPlan inf = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, true, CGRectMake(0, 0, INFINITY, 0), true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(inf.rail, "inf rail");
    NFBRailPlan z = NFBPlanRail(0, 0, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(z.rail, "zero rail");
#endif

#if NFB_RAIL_PORT
    NFBRailPlan longl = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false, 0.7, true, 0, 8, 0, split.rowsTop, split.diameter, W, true);
    check(CGRectGetHeight(longl.rail) > 2 * 57, "long list viewport");
    check(NFBSplitMetricsValid(48, 0, W, W), "valid metric"); check(!NFBSplitMetricsValid(0, 0, W, W), "zero metric");
    check(!NFBSplitMetricsValid(48, 0, W, W - 20), "rotated metric");
    printf("PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)\n");
    return 0;

#endif

    printf("PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)\n");
    return 0;
}
