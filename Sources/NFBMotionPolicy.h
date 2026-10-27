#pragma once
#include <stdbool.h>

// Animation rules for the notification column, shared by the manager and the
// portable tests (no UIKit/Foundation needed).
//
// 1. A repeating layout pass (20 Hz refresh, split watcher, tick) must not submit
//    an animation for values that did not change. Re-adding the same 0.35s curve
//    at 20 Hz kept the column in a permanent spring, so a real move (or an alpha
//    change) looked like a jump the moment it finally happened.
// 2. An animation completion must not tear down a view that a newer pass adopted.
//    Tokens make the check explicit instead of relying on object identity alone.
// 3. The unread badge animates only when its content changed, never on a pass
//    that re-lays out the same count.

static inline bool NFBMotionNeedsAnimation(double current, double target) {
    if (current != current || target != target) return false;          // NaN guard
    double delta = target - current;
    if (delta < 0) delta = -delta;
    return delta > 0.001;
}

// True when any axis of a frame moved enough to be worth animating.
static inline bool NFBMotionRectMoved(double x, double y, double width, double height,
        double targetX, double targetY, double targetWidth, double targetHeight) {
    return NFBMotionNeedsAnimation(x, targetX) || NFBMotionNeedsAnimation(y, targetY) ||
        NFBMotionNeedsAnimation(width, targetWidth) || NFBMotionNeedsAnimation(height, targetHeight);
}

// A completion may only apply its result while it is still the current owner.
static inline bool NFBMotionCompletionIsCurrent(unsigned long long captured, unsigned long long current) {
    return captured == current;
}

// Badge: only a content change (text appearing/vanishing, or a different count)
// may restart the pill animation.
static inline bool NFBBadgeNeedsAnimation(bool hadText, bool hasText, double previous, double count) {
    if (hadText != hasText) return true;
    if (previous != previous || count != count) return hadText != hasText;  // NaN guard
    double delta = count - previous;
    if (delta < 0) delta = -delta;
    return delta >= 0.5;
}
