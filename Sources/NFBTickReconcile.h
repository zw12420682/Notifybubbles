#pragma once
#include <stdbool.h>
#include <stddef.h>

// What the 2 Hz tick must notice on its own (NFBManager -tickBody).
//
// The tick used to call a full layout every 0.5s. It now compares the state a
// layout would read and only lays out when something changed. That is only
// sound if *every* state the layout depends on is in this comparison: a state
// that is missing here is never detected, because nothing else in the tick
// looks at it. In particular:
//
//   * the frontmost app (a fullscreen app entering or leaving the column),
//   * home vs. an app (the split's attachment target),
//   * a badge count changing without a new record (system-side withdraw that
//     reached us as an icon badge only),
//
// must be compared here. "The layout re-reads state whenever it runs" is not
// enough: the layout only runs when *this* function says it is needed.
//
// Comparison is by value: ids travel as interned strings, so an unchanged app
// compares equal without the caller allocating anything per tick.

typedef struct {
    // Frontmost app id, or NULL/empty for the home screen and for "unknown".
    const char *front;
    // Home screen (springboard) is showing. Distinct from an empty front app:
    // an unreadable front app is not the home screen.
    bool home;
    // Count of the notification column's own unread records, summed over the
    // apps the layout builds bubbles for.
    long unread;
    // Lock screen showing.
    bool locked;
    // Keyboard showing (it pulls the whole column offscreen).
    bool keyboard;
    // Column expanded by the user (the 5s auto-fold state).
    bool expanded;
    // Split column in use (a floating window owns the right side).
    bool split;
    // Last layout finished incomplete and must be redone.
    bool incomplete;
    // Screenshot privacy / enabled and the capture flag reached the layout.
    bool captureHidden;
} NFBTickState;

static inline bool NFBTickTextEqual(const char *a, const char *b) {
    if (a == b) return true;
    // NULL and "" are the same "no app".
    if (!a) a = "";
    if (!b) b = "";
    while (*a && *a == *b) { ++a; ++b; }
    return *a == *b;
}

// True when a full layout is required this tick. `forced` is set by callers that
// know a layout is pending regardless of state (a just-finished burst, a
// collapsed edge that still owes its fold); `first` is the tick's very first
// comparison after being enabled, when nothing has been laid out yet.
static inline bool NFBTickNeedsLayout(const NFBTickState *previous, const NFBTickState *current,
                                      bool forced, bool first) {
    if (first || forced) return true;
    if (!previous || !current) return true;
    if (!NFBTickTextEqual(previous->front, current->front)) return true;
    if (previous->home != current->home) return true;
    if (previous->unread != current->unread) return true;
    if (previous->locked != current->locked) return true;
    if (previous->keyboard != current->keyboard) return true;
    if (previous->expanded != current->expanded) return true;
    if (previous->split != current->split) return true;
    if (previous->incomplete != current->incomplete) return true;
    if (previous->captureHidden != current->captureHidden) return true;
    return false;
}
