#import <Foundation/Foundation.h>
#import "NFBRailLayout.h"

// Geometry regression tests for the fullscreen column. No UIKit views: the plan
// is the same function the manager lays out from, so a control drifting to the
// bottom-right, favorites eating the main rail's height, or icons changing size
// between split and fullscreen fails here.

static void check(bool condition, NSString *message) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
}
static void close(double a, double b, NSString *message) {
    check(isfinite(a) && isfinite(b) && fabs(a - b) < 0.51, [message stringByAppendingFormat:@" (%f vs %f)", a, b]);
}
static void finiteRect(CGRect rect, NSString *message) {
    check(isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
          isfinite(rect.size.width) && isfinite(rect.size.height), message);
    check(rect.size.width >= 0 && rect.size.height >= 0, [message stringByAppendingString:@" negative size"]);
    check(fabs(rect.origin.x) < 10000 && fabs(rect.origin.y) < 10000, [message stringByAppendingString:@" runaway origin"]);
}

int main(void) {
    const double W = 390, H = 844, TOP = 90;
    UIEdgeInsets safe = UIEdgeInsetsMake(59, 0, 34, 0);
    CGRect splitFrame = CGRectMake(0, 422, 195, 422);         // bottom-left corner split (maxY = 844)
    CGFloat splitTop = 422 + 422 * 0.05;  // NFBSplitRailTop(422, 422)
    double splitAngle = 0.80;

    // 1. Split baseline: the action owns the first row at the rail top.
    NFBRailPlan split = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, true, splitFrame, true,
        0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(split.rail, @"split rail");
    close(split.diameter, 48, @"split diameter is the settings size");
    // The rail plan itself starts the split rows at the split top; the desktop
    // action shares that row and is therefore never inside the scrolling rail.
    finiteRect(split.rail, @"split rail geometry");
    check(CGRectGetHeight(split.rail) > 62, @"split rail keeps usable height");
    check(!split.parked, @"split never parks the control");

    // 2. Fullscreen expanded reuses the remembered split top and diameter, only
    //    horizontally attached to the right screen edge.
    NFBRailPlan open = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, false, 2, 3, 0, split.rowsTop, split.diameter, W, true);
    finiteRect(open.rail, @"expanded rail");
    close(open.diameter, split.diameter, @"expanded diameter equals split diameter");
    check(open.toggleVisible, @"expanded shows the collapse control");
    close(open.toggle.origin.y, split.rowsTop, @"expanded control sits exactly on the split row");
    check(open.toggle.origin.y < 844 - 62 - 34, @"expanded control is not pinned at the bottom-right");
    close(open.toggle.origin.x, NFBCollapsedRailFrameX(W, split.diameter + 14, 4), @"expanded control hugs the right edge");
    check(CGRectGetWidth(open.toggle) > 20 && CGRectGetWidth(open.toggle) < 200, @"control has a sane size");
    check(open.favoritesVisible && open.favoriteHeight > 0, @"expanded shows favorites");
    check(open.rail.origin.y > open.toggle.origin.y, @"expanded rail hangs below the control");
    check(CGRectGetHeight(open.rail) >= open.diameter + 14, @"expanded main rail keeps a full row");
    check(!open.parked, @"expanded never parks");

    // 3. A wide split narrows the icon size; fullscreen must reuse that value.
    CGRect wide = CGRectMake(0, 422, 340, 422);
    NFBRailPlan squeezed = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, true, wide, true,
        0.7, false, 2, 3, 0, 0, 0, 0, false);
    check(squeezed.diameter < 48, @"a tight split squeezes the diameter");
    NFBRailPlan afterSqueeze = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, false, 2, 3, 0, squeezed.railTop, squeezed.diameter, W, true);
    close(afterSqueeze.diameter, squeezed.diameter, @"fullscreen reuses the squeezed split diameter");

    // 4. Fullscreen collapsed with unread apps: same top/diameter, unread only,
    //    no favorites taking height, control parked at the edge.
    NFBRailPlan collapsed = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, true, 0, 2, 0, split.rowsTop, split.diameter, W, true);
    finiteRect(collapsed.rail, @"collapsed rail");
    close(collapsed.diameter, split.diameter, @"collapsed diameter equals split diameter");
    check(collapsed.rail.origin.y > collapsed.toggle.origin.y, @"collapsed rail hangs below the control");
    close(collapsed.toggle.origin.y, open.toggle.origin.y, @"collapsed control keeps the expanded y");
    close(collapsed.toggle.origin.x, W - 7 - split.diameter / 2, @"half-hidden image center is the screen edge");
    check(CGRectGetHeight(collapsed.rail) >= collapsed.diameter + 14, @"collapsed main rail is not crushed");
    check(!collapsed.favoritesVisible && collapsed.favoriteHeight == 0, @"hidden favorites take no height");
    check(collapsed.parked, @"collapsed parks the control");
    check(collapsed.toggle.origin.x + CGRectGetWidth(collapsed.toggle) > W, @"parked control crosses the edge");

    // 5. No notifications: nothing but the control, same place, still half hidden.
    NFBRailPlan empty = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, true, 0, 0, 0, split.rowsTop, split.diameter, W, true);
    close(empty.toggle.origin.y, collapsed.toggle.origin.y, @"empty control y equals the notified one");
    close(empty.toggle.origin.x, collapsed.toggle.origin.x, @"empty control x equals the notified one");
    close(CGRectGetWidth(empty.toggle), CGRectGetWidth(collapsed.toggle), @"empty control size unchanged");
    check(empty.parked && NFBToggleShouldFade(empty.parked, true), @"empty control stays half hidden");
    finiteRect(empty.rail, @"empty rail");

    // 6. The favorites count never changes the collapsed rail height.
    NFBRailPlan manyFavorites = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, true, 5, 2, 0, split.rowsTop, split.diameter, W, true);
    check(fabs(CGRectGetHeight(manyFavorites.rail) - CGRectGetHeight(collapsed.rail)) < 0.51,
          @"rail height is independent of the favorites count");
    check(fabs(manyFavorites.rail.origin.y - collapsed.rail.origin.y) < 0.51,
          @"rail top is independent of the favorites count");

    // 7. Expanded with no notifications does not park (no half-hiding).
    NFBRailPlan openEmpty = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, false, 3, 3, 0, split.rowsTop, split.diameter, W, true);
    check(!openEmpty.parked && !NFBToggleShouldFade(openEmpty.parked, true), @"expanded empty does not fade");
    close(openEmpty.toggle.origin.x, W - (split.diameter + 14) - 4, @"expanded empty stays fully on screen");

    // 8. No remembered split: a sane finite default at the top, not the bottom.
    NFBRailPlan first = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(first.toggle, @"default control");
    close(first.toggle.origin.y, TOP, @"default control sits at the top of the column");
    check(first.toggle.origin.y < H / 2, @"default control is not near the bottom");
    close(first.diameter, 48, @"default diameter is the settings size");

    // 9. A rotated screen invalidates the remembered metric (no size mismatch).
    NFBRailPlan rotated = NFBPlanRail(H, W, safe, TOP, 52, splitAngle, false, CGRectZero, false,
        0.7, false, 2, 3, 0, split.rowsTop, split.diameter, W, true);
    close(rotated.diameter, 52, @"rotation drops the stale split diameter");
    finiteRect(rotated.rail, @"rotated rail");
    finiteRect(rotated.toggle, @"rotated control");

    // 10. Hostile inputs never produce NaN/inf frames.
    NFBRailPlan nan = NFBPlanRail(NAN, H, safe, TOP, NAN, splitAngle, false, CGRectZero, false,
        NAN, true, 0, 0, 0, NAN, NAN, NAN, true);
    finiteRect(nan.rail, @"nan rail");
    finiteRect(nan.toggle, @"nan toggle");
    NFBRailPlan inf = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, true, CGRectMake(0, 0, INFINITY, 0),
        true, 0.7, false, 2, 3, 0, 0, 0, 0, false);
    finiteRect(inf.rail, @"inf split rail");
    NFBRailPlan zero = NFBPlanRail(0, 0, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, true, 0, 0, 0, 0, 0, 0, false);
    finiteRect(zero.rail, @"zero screen rail");

    // 11. A long collapsed list keeps its full content height (no crushed rail).
    NFBRailPlan longList = NFBPlanRail(W, H, safe, TOP, 48, splitAngle, false, CGRectZero, false,
        0.7, true, 0, 8, 8, split.rowsTop, split.diameter, W, true);
    check(CGRectGetHeight(longList.rail) > 2 * (split.diameter + 9),
          @"a long unread list keeps a scrollable viewport instead of a hairline");
    check(NFBSplitMetricsValid(48, 0, W, W), @"valid split metric accepted");
    check(!NFBSplitMetricsValid(0, 0, W, W), @"zero diameter rejected");
    check(!NFBSplitMetricsValid(48, 0, W, W - 20), @"rotated width rejected");

    printf("PASS: column geometry (split -> fullscreen expanded -> collapsed -> empty)\n");
    return 0;
}
