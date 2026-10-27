#pragma once
#include <stdbool.h>
#include <stddef.h>

// Same-round probe reuse for the two probes the column runs on its 20 Hz path.
//
// `refresh` probes the desktop (split) window and the floating app; the floating
// watcher probes the same two things again on every 20 Hz fire, so one round of
// the runloop could ask SpringBoard for the same window state twice - once per
// pass - before either pass had a chance to act on it. A probe is now reused
// inside the same round (same main-runloop turn, within a few milliseconds) by
// the other path; every other fire still probes for real, so the watcher keeps
// its 20 Hz timing, its explicit invalidation on a nil class and its late retry.
//
// The rule for reusing a probe:
//   * it must belong to the same round: the object identity touched by this
//     turn's entry point. A later turn touches a new object, so nothing is ever
//     reused across turns even if the timers fire closer than one frame;
//   * only a *usable* answer is reused. A nil class / nil window / empty app is a
//     transient SpringBoard state that refresh must retry immediately (the
//     "nil class, probe again next tick" path), never inherit from the watcher.
typedef struct {
    bool resolved;        // a probe ran and produced a usable answer
    bool usable;          // that answer was usable (window found)
    const void *round;    // the turn the probe ran in (object identity, NULL = none)
    double stamp;         // CACurrentMediaTime of the probe (diagnostics)
} NFBProbeStamp;

// How long a "the split class is not up yet" answer suppresses reuse.
#define NFBProbeLateRetry 0.2

static inline bool NFBProbeReusable(NFBProbeStamp stamp, const void *round, double lateRetryAt, double now) {
    if (!stamp.resolved || !stamp.usable) return false;
    // A pending late retry always wins over any remembered answer.
    if (lateRetryAt > now) return false;
    // Same round only: the object identity of this turn's entry point.
    return round != NULL && stamp.round == round;
}

static inline NFBProbeStamp NFBProbeRecord(NFBProbeStamp previous, bool usable, const void *round, double now) {
    previous.resolved = true;
    previous.usable = usable;
    previous.round = round;
    previous.stamp = now;
    return previous;
}
