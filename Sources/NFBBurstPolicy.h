#pragma once
#include <stdbool.h>

// What a notice that arrived while a burst was being coalesced may still do to
// the bubble afterwards.
//
// A burst of notifications (one app posting several, or several apps at once)
// used to run one full layout per request: the last layout of the burst landed on
// top of the shake/scroll of every earlier one, so bubbles were shaken while the
// rail was still being rebuilt around them. The manager now lays the burst out
// once, and only after that pass has placed the bubbles does it replay the
// reminder effects for the apps that still own a bubble. This header holds that
// decision so it is testable without UIKit.
typedef struct {
    bool windowVisible;   // the column window is on screen
    bool hasBubble;       // the layout pass really created/found a bubble for the app
    bool inSplit;         // an app occupies the split view (else there is nothing to shout at)
    bool synthetic;       // the clear-all pseudo app never shakes
    bool reduceMotion;    // a shake is motion: skip it, exactly as before
    bool rowVisible;      // the bubble ended up inside its scroll container's bounds
} NFBBurstEffectInput;

// The shake is the pre-existing reminder for a message that arrives while an app
// sits in the split view; it keeps its exact condition, only its *timing* moves
// after the layout that produced the bubble.
static inline bool NFBBurstShouldShake(NFBBurstEffectInput in) {
    if (!in.windowVisible || !in.hasBubble) return false;
    if (!in.inSplit || in.synthetic) return false;
    if (in.reduceMotion) return false;
    return true;
}

// The scroll only exists to bring the freshly shaken row into view; on the lock
// screen the window is visible but the user cannot act on it, so it is skipped
// there just like the manager already skipped it.
static inline bool NFBBurstShouldScroll(NFBBurstEffectInput in) {
    if (!in.windowVisible || !in.hasBubble) return false;
    if (in.synthetic) return false;
    return !in.rowVisible;
}
