#pragma once
#include <stdbool.h>

// Column slide + keyboard visibility decisions, shared verbatim by the manager
// (Sources/NFBManager.m, Sources/NFBKeyboard.m) and the portable tests.
// Keep the existing simulator regression enabled when validating this policy.
//
// Only the *decision* lives here; timings, curves and the animations themselves
// stay in the production files (out 0.24s ease-in, in 0.28s delay 0.04s).
//
// Column: `refresh` runs at 20 Hz and re-asks for the keyboard state every pass.
// A probe that lags one pass must not turn "already hidden" / "already shown"
// into a new submission - that resubmit is the visible flash.

// A slide that is neither in flight nor already committed is idle. `touches`
// is false when reduce-motion or a missing root dropped the column to an
// instant `hidden` flip (the view's transform alone lies then).
static inline bool NFBColumnMotionIdle(bool sliding, bool touches, bool identity,
                                       bool parked, bool hidden) {
    if (sliding) return false;
    if (hidden) return identity || !touches;
    return parked;
}

// A request equal to the state already committed never needs a new slide.
static inline bool NFBColumnSlideNeeded(bool offscreen, bool current) {
    return offscreen != current;
}

// The reveal starts at the right edge only from a parked column; otherwise it
// continues from the current position (never snaps away first).
static inline bool NFBColumnRevealStartAway(bool touches, bool identity, bool parked) {
    return touches && identity && parked;
}

// A slide completion may commit only if no newer slide took the token and the
// direction it was started for is still the target.
static inline bool NFBColumnCompletionApplies(unsigned long token, unsigned long latest,
                                              bool target, bool direction) {
    return token == latest && target == direction;
}

// An off-screen flip may be committed only against the transform the slide was
// built from; anything else means the render tree was rebuilt meanwhile.
static inline bool NFBColumnTransformMatches(bool identity, bool targetIdentity) {
    return identity == targetIdentity;
}

// Keyboard visibility.
//
// `notified` is the notification half (Will/DidShow without a later hide),
// `hiddenSince` marks a WillHide that a DidHide has not confirmed yet, and
// `probeUp` is the throttled window/system probe, bounded by its own TTL so a
// SpringBoard/app keyboard that publishes no notification still keeps the
// column out of the way. Any one source reporting up is enough.
typedef struct {
    bool notified;
    bool hiddenSince;
    bool staleDidHide;   // a DidHide that no WillHide/WillShow announced
} NFBKeyboardTrack;

// The single show entry point: a WillShow, or a DidShow that is not the
// duplicate of an announced hide, both mean "up from now on".
static inline NFBKeyboardTrack NFBKeyboardShow(NFBKeyboardTrack t, bool duplicate) {
    if (duplicate) return t;
    t.notified = true; t.hiddenSince = false; t.staleDidHide = false;
    return t;
}

static inline bool NFBKeyboardDidShowIsDuplicate(const NFBKeyboardTrack t) {
    return t.hiddenSince;
}

static inline NFBKeyboardTrack NFBKeyboardWillHide(NFBKeyboardTrack t) {
    if (t.hiddenSince) return t;            // duplicate WillHide
    t.notified = false; t.hiddenSince = true; t.staleDidHide = false;
    return t;
}

static inline bool NFBKeyboardWillHideIsDuplicate(const NFBKeyboardTrack t) {
    return t.hiddenSince;
}

// Returns the track with the hide confirmed. `announced` = a WillHide is
// pending; a DidHide without one is stale and is dropped rather than clearing
// the notified state a newer WillShow may have just set.
static inline NFBKeyboardTrack NFBKeyboardDidHide(NFBKeyboardTrack t, bool *confirmed) {
    if (confirmed) *confirmed = t.hiddenSince;
    if (t.hiddenSince) { t.hiddenSince = false; return t; }
    t.staleDidHide = true;
    return t;
}

static inline bool NFBKeyboardCombined(const NFBKeyboardTrack t, bool probeUp, bool hiddenGrace) {
    return !hiddenGrace && (t.notified || probeUp);
}

// The 0.45s window after a WillHide in which the probes still see the keyboard
// animating out and must not count.
static inline bool NFBKeyboardHiddenGrace(double now, double hiddenAt) {
    return hiddenAt > 0 && now - hiddenAt < 0.45;
}
