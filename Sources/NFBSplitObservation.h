#pragma once
#include <stdbool.h>
// A missing class/scene is not proof that an app window has closed.
typedef enum { NFBSplitObservationUnknown, NFBSplitObservationPresent, NFBSplitObservationAbsent } NFBSplitObservation;
typedef struct { unsigned missing; } NFBSplitObservationTracker;
// Unknown is bounded, not an indefinite lease. Explicit disabled/locked always
// releases immediately. A reliable absence needs two successive observations.
static inline bool NFBSplitRetainMovie(NFBSplitObservationTracker *t, bool wasActive,
        bool enabled, NFBSplitObservation obs) {
    if (!enabled) { t->missing=0; return false; }
    if (obs==NFBSplitObservationPresent) { t->missing=0; return true; }
    if (!wasActive) { t->missing=0; return false; }
    if (++t->missing <= 2) return true;
    return false;
}
