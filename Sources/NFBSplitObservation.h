#pragma once
#include <stdbool.h>
// A missing class/scene is not proof that an app window has closed.
typedef enum { NFBSplitObservationUnknown, NFBSplitObservationPresent, NFBSplitObservationAbsent } NFBSplitObservation;
typedef struct { unsigned missing; } NFBSplitObservationTracker;
// Unknown is bounded, not an indefinite lease. Explicit disabled/locked always
// releases immediately. Two missing samples are tolerated; the third releases the old leases.
static inline bool NFBSplitRetainMovie(NFBSplitObservationTracker *t, bool wasActive,
        bool enabled, NFBSplitObservation obs) {
    if (!enabled) { t->missing=0; return false; }
    if (obs==NFBSplitObservationPresent) { t->missing=0; return true; }
    if (!wasActive) { t->missing=0; return false; }
    if (++t->missing <= 2) return true;
    return false;
}

// Only use explicit closure when all previously observed landscape windows
// are gone/detached or report closing. Hidden/minimized is NOT proof of close.
static inline bool NFBSplitRetainMovieWithClosure(NFBSplitObservationTracker *t,
        bool wasActive, bool enabled, NFBSplitObservation obs, bool closed) {
    if (closed && obs!=NFBSplitObservationPresent) { t->missing=0; return false; }
    return NFBSplitRetainMovie(t,wasActive,enabled,obs);
}
