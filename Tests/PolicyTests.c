// 0.48.88 regression tests: the policies below are the ones the manager itself
// runs (Sources/*Policy.h are pure C, no UIKit/Foundation).
//
// Built (and built with -Werror) on every platform by scripts/test_policies.py,
// which is also a CI step; the header-only policies mean the test exercises the
// exact code the tweak compiles, with no copies and no mocks of the logic.
#include <stdio.h>
#include <stdbool.h>
#include <math.h>

static int debug_line;
#define check(c, w) (debug_line = __LINE__, check_impl((c), (w)))

#include "NFBDesktopActionPolicy.h"
#include "NFBBurstPolicy.h"
#include "NFBFavoriteDragPolicy.h"
#include "NFBProbePolicy.h"
#include "NFBRailMetricQueue.h"
#include "NFBTickReconcile.h"

static int failures;

static void check_impl(bool condition, const char *what) {
    if (condition) return;
    ++failures;
    printf("FAIL: %s (line %d)\n", what, debug_line);
}

static NFBRailMetric metric(double top, double diameter, double width) {
    NFBRailMetric m;
    m.top = top;
    m.diameter = diameter;
    m.screenWidth = width;
    return m;
}

static void testDesktopActionAnimation(void) {
    // Every target identical: the 20 Hz passes must not submit an animation.
    NFBDesktopActionInput same = {false, 100, 60, 62, 62, 100, 60, 62, 62, 1, 1, 48, 48};
    check(!NFBDesktopActionNeedsAnimation(same), "identical targets must not animate");
    NFBDesktopActionInput hidden = same;
    hidden.alpha = 0; hidden.targetAlpha = 0;
    check(!NFBDesktopActionNeedsAnimation(hidden), "identical hidden targets must not animate");
    // A real move/alpha/appearance still animates (the existing curve applies).
    NFBDesktopActionInput moved = same;
    moved.targetY = 61.5;
    check(NFBDesktopActionNeedsAnimation(moved), "a moved slot must animate");
    NFBDesktopActionInput faded = same;
    faded.targetAlpha = 0.5;
    check(NFBDesktopActionNeedsAnimation(faded), "a parked fade must animate");
    NFBDesktopActionInput gone = same;
    gone.targetAlpha = 0;
    check(NFBDesktopActionNeedsAnimation(gone), "hiding must animate");
    NFBDesktopActionInput growing = same;
    growing.targetImageWidth = 34;
    check(NFBDesktopActionNeedsAnimation(growing), "an icon resize must animate");
    NFBDesktopActionInput appearing = same;
    appearing.appearing = true;
    check(NFBDesktopActionNeedsAnimation(appearing), "appearing from hidden must animate");
    NFBDesktopActionInput subpixel = same;
    subpixel.targetX = 100.0005;
    check(!NFBDesktopActionNeedsAnimation(subpixel), "sub-0.001 jitter must not animate");
    NFBDesktopActionInput nan = same;
    nan.targetX = NAN;
    check(!NFBDesktopActionNeedsAnimation(nan), "a NaN target is never animated");
}

static void testBurst(void) {
    NFBBurstEffectInput in = {true, true, true, false, false, true};
    check(NFBBurstShouldShake(in), "split reminder shakes a placed bubble");
    NFBBurstEffectInput beforeLayout = in;
    beforeLayout.hasBubble = false;
    check(!NFBBurstShouldShake(beforeLayout), "no shake before the bubble is laid out");
    NFBBurstEffectInput noSplit = in;
    noSplit.inSplit = false;
    check(!NFBBurstShouldShake(noSplit), "no shake outside a split");
    NFBBurstEffectInput reduce = in;
    reduce.reduceMotion = true;
    check(!NFBBurstShouldShake(reduce), "reduce motion keeps its old rule");
    NFBBurstEffectInput clearAll = in;
    clearAll.synthetic = true;
    check(!NFBBurstShouldShake(clearAll), "the clear-all control never shakes");
    NFBBurstEffectInput hidden = in;
    hidden.windowVisible = false;
    check(!NFBBurstShouldShake(hidden) && !NFBBurstShouldScroll(hidden),
        "a hidden column runs neither effect");
    check(NFBBurstShouldScroll(in) == false, "a visible row is not scrolled");
    NFBBurstEffectInput offscreen = in;
    offscreen.rowVisible = false;
    check(NFBBurstShouldScroll(offscreen), "an offscreen row is scrolled into view");
}

static void testFavoriteDrag(void) {
    // Middle of the list, nothing to auto-scroll: no idle clock at all.
    NFBFavoriteDragInput middle = {true, 200, 300, 1200, 100, false};
    check(!NFBFavoriteIdleClockActive(middle, 44), "no clock outside the edge zones");
    check(!NFBFavoriteEdgeNeedsMove(middle), "the clock does nothing outside the zones");
    // Top edge with room to scroll up (offset > 0): clock runs.
    NFBFavoriteDragInput top = {true, 10, 300, 1200, 100, false};
    check(NFBFavoriteIdleClockActive(top, 44), "top edge with room starts the clock");
    check(NFBFavoriteEdgeNeedsMove(top), "top edge keeps moving every frame");
    // Top edge already at the very top: one frame source only (the finger).
    NFBFavoriteDragInput topAtZero = {true, 10, 300, 1200, 0, false};
    check(!NFBFavoriteIdleClockActive(topAtZero, 44), "top edge at offset 0 needs no clock");
    NFBFavoriteDragInput topAtZeroMoved = topAtZero;
    topAtZeroMoved.fingerMoved = true;
    check(NFBFavoriteEdgeNeedsMove(topAtZeroMoved), "a moved finger still moves the row");
    NFBFavoriteDragInput bottom = {true, 290, 300, 1200, 800, false};
    check(NFBFavoriteIdleClockActive(bottom, 44) && NFBFavoriteEdgeNeedsMove(bottom),
        "bottom edge with room starts the clock");
    NFBFavoriteDragInput bottomEnd = {true, 290, 300, 1200, 900, false};
    check(!NFBFavoriteIdleClockActive(bottomEnd, 44), "bottom edge at the end needs no clock");
    NFBFavoriteDragInput shortList = {true, 5, 300, 200, 0, false};
    check(!NFBFavoriteIdleClockActive(shortList, 44), "a list that fits never auto-scrolls");
    NFBFavoriteDragInput idle = {false, 5, 300, 1200, 0, false};
    check(!NFBFavoriteIdleClockActive(idle, 44), "no clock without a drag");
    // Half-open edge zones: exactly 44pt is no longer the zone.
    NFBFavoriteDragInput boundary = {true, 44, 300, 1200, 100, false};
    check(!NFBFavoriteIdleClockActive(boundary, 44), "edge boundary is half-open");
}

static void testLatestPendingMetric(void) {
    NFBRailMetricQueue q = NFBRailMetricQueueLoaded(NFBRailMetricNoRecord(), false);
    NFBRailMetric a = metric(100, 48, 390), b = metric(104, 48, 390), c = metric(108, 48, 390);
    check(NFBRailMetricQueueOffer(&q, a), "A starts the debounce clock");
    check(!NFBRailMetricQueueOffer(&q, b), "B joins the running clock");
    check(!NFBRailMetricQueueOffer(&q, c), "C joins the running clock");
    NFBRailMetric out = NFBRailMetricNoRecord();
    check(NFBRailMetricQueueDrain(&q, &out), "the clock has a pending metric");
    check(NFBRailMetricEqual(out, c), "A,B,C => C is written, not the first captured");
    NFBRailMetricQueueCommitted(&q, out);
    // Returning to the committed geometry: nothing to write, no clock.
    check(!NFBRailMetricQueueOffer(&q, c), "equal to disk needs no write");
    NFBRailMetricQueueCommitted(&q, b);
    // Invalid geometry is ignored and never cancels a pending valid write.
    check(NFBRailMetricQueueOffer(&q, a), "a real change starts a new clock");
    NFBRailMetricQueueCommitted(&q, a);
    NFBRailMetric bad = metric(-5, 48, 390);
    check(!NFBRailMetricQueueOffer(&q, bad), "unusable geometry is ignored");
    check(q.pending, "an unusable offer keeps the pending write");
    NFBRailMetric nan = metric(NAN, 48, 390);
    check(!NFBRailMetricQueueOffer(&q, nan), "NaN geometry is ignored");
    NFBRailMetric tiny = metric(10, 2, 390);
    check(!NFBRailMetricQueueOffer(&q, tiny), "an impossible icon size is ignored");
    // Still pending after the invalid offers: it is the same write, no new clock.
    check(!NFBRailMetricQueueOffer(&q, a), "the pending write already holds A");
    check(q.pending, "A is still the pending write");
    // With an empty clock a valid change starts it again.
    {
        NFBRailMetric drained = NFBRailMetricNoRecord();
        NFBRailMetricQueueDrain(&q, &drained);
    }
    // Invalid while valid is pending: the pending write survives untouched.
    check(NFBRailMetricQueueOffer(&q, b), "B starts a clock");
    NFBRailMetricQueueOffer(&q, bad);
    NFBRailMetricQueueDrain(&q, &out);
    check(NFBRailMetricEqual(out, b), "an invalid offer does not replace the pending metric");
    check(!q.pending, "the clock is consumed");
    check(!NFBRailMetricQueueDrain(&q, &out), "an empty clock yields nothing");
}

static void testProbeReuse(void) {
    double now = 100.0;
    NFBProbeStamp none = {false, false, NULL, 0};
    int roundA = 1, roundB = 2;
    check(!NFBProbeReusable(none, &roundA, 0, now), "an unrun probe is never reused");
    NFBProbeStamp stamp = NFBProbeRecord(none, true, &roundA, now);
    check(NFBProbeReusable(stamp, &roundA, 0, now + 0.001), "same round is reused");
    check(!NFBProbeReusable(stamp, &roundB, 0, now + 0.05), "next round probes again");
    check(!NFBProbeReusable(stamp, NULL, 0, now), "without a round identity nothing is reused");
    check(!NFBProbeReusable(stamp, &roundA, now + 0.2, now), "a late retry suppresses reuse");
    NFBProbeStamp nilAnswer = NFBProbeRecord(stamp, false, &roundA, now);
    check(!NFBProbeReusable(nilAnswer, &roundA, 0, now), "a nil answer is never reused");
}

static void testTickReconcile(void) {
    NFBTickState base = {"com.example.app", false, 2, false, false, false, false, false, true};
    check(!NFBTickNeedsLayout(&base, &base, false, false), "an unchanged tick must not lay out");
    check(NFBTickNeedsLayout(&base, &base, true, false), "a forced refresh always lays out");
    check(NFBTickNeedsLayout(NULL, &base, false, false), "no previous state lays out once");
    check(NFBTickNeedsLayout(&base, &base, false, true), "the first tick lays out");
    // The frontmost app alone is an edge: entering or leaving the column.
    NFBTickState other = base; other.front = "com.example.other";
    check(NFBTickNeedsLayout(&base, &other, false, false), "a front app change lays out");
    NFBTickState none = base; none.front = NULL;
    check(NFBTickNeedsLayout(&base, &none, false, false), "front app -> no front app lays out");
    NFBTickState empty = base; empty.front = "";
    check(!NFBTickNeedsLayout(&none, &empty, false, false), "NULL and empty read as the same");
    // Home screen is state even when the front app is unreadable (NULL/empty).
    NFBTickState home = none; home.home = true;
    check(NFBTickNeedsLayout(&none, &home, false, false), "home appearing lays out");
    check(NFBTickNeedsLayout(&home, &none, false, false), "leaving home lays out");
    // A badge count that changes without a new record.
    NFBTickState badge = base; badge.unread = 3;
    check(NFBTickNeedsLayout(&base, &badge, false, false), "an unread count change lays out");
    NFBTickState zero = base; zero.unread = 0;
    check(NFBTickNeedsLayout(&base, &zero, false, false), "clearing unread lays out");
    // Every remaining field is compared, not assumed.
    NFBTickState lock = base; lock.locked = true;
    check(NFBTickNeedsLayout(&base, &lock, false, false), "lock lays out");
    NFBTickState keyboard = base; keyboard.keyboard = true;
    check(NFBTickNeedsLayout(&base, &keyboard, false, false), "keyboard lays out");
    NFBTickState expanded = base; expanded.expanded = true;
    check(NFBTickNeedsLayout(&base, &expanded, false, false), "expand/fold lays out");
    NFBTickState split = base; split.split = true;
    check(NFBTickNeedsLayout(&base, &split, false, false), "split lays out");
    NFBTickState incomplete = base; incomplete.incomplete = true;
    check(NFBTickNeedsLayout(&base, &incomplete, false, false), "an incomplete layout lays out");
    NFBTickState capture = base; capture.captureHidden = false;
    check(NFBTickNeedsLayout(&base, &capture, false, false), "a privacy change lays out");
    // An identical *copy* (different storage) is still equal: by value, not by pointer.
    NFBTickState copy = base;
    char front[32] = "com.example.app";
    copy.front = front;
    check(!NFBTickNeedsLayout(&base, &copy, false, false), "equal ids from different storage lay out never");

    // Bounded reconciliation (NFBTickReconcile.h): identical state, but a full
    // layout is forced at least every NFBTickReconcileInterval seconds, so a badge
    // that changed outside our records cannot stay stale forever. The bound is
    // aggressive enough that a 2 Hz tick hits it within a few ticks, and it never
    // fires below the interval.
    check(!NFBTickReconcileDue(0.5), "half a second of identical state does not force a layout");
    check(!NFBTickReconcileDue(1.999), "just under the bound still dedupes");
    check(NFBTickReconcileDue(NFBTickReconcileInterval), "the bound forces a layout");
    check(NFBTickReconcileDue(5.0), "a long quiet stretch forces one at every tick after the bound");
    check(NFBTickReconcileInterval <= 2.0, "the backstop is at most 2s, not a nominal guard");
    // A quiet stretch: the tick counts from the last real layout, which it stamps
    // itself when the backstop forces one, so 10 ticks over 5s lay out 2 times
    // (t=2.0 and t=4.0) instead of 10.
    int forced = 0;
    double lastLayout = 0;
    for (int tick = 1; tick <= 10; ++tick) {
        double now = tick * 0.5;
        if (NFBTickReconcileDue(now - lastLayout)) { ++forced; lastLayout = now; }
    }
    check(forced == 2, "a 10-tick (5s) quiet stretch forces exactly 2 full layouts");
    // `forced` (the tick's own dirty state) and the backstop are independent reasons.
    check(NFBTickNeedsLayout(&base, &base, true, false), "the reconcile reason alone lays out");
}

int main(void) {
    testDesktopActionAnimation();
    testBurst();
    testFavoriteDrag();
    testLatestPendingMetric();
    testTickReconcile();
    testProbeReuse();
    if (failures) {
        printf("FAIL: %d policy checks\n", failures);
        return 1;
    }
    printf("PASS: layout/burst/drag/metric/tick/probe policies\n");
    return 0;
}
