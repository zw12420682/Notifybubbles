#pragma once
#include <stdbool.h>
#include <stdint.h>

// Shared by production code and portable tests: no UIKit or Foundation needed.
static inline bool NFBTransitionNeedsAction(uint64_t epoch, uint64_t applied) { return epoch != applied; }
static inline bool NFBTransitionStable(double now, double since) { return now - since >= 0.12; }
static inline bool NFBExitStillCurrent(uint64_t captured, uint64_t current,
                                     bool enabled, bool reopened, bool batchProtected) {
    return enabled && captured == current && !reopened && !batchProtected;
}
static inline bool NFBShouldRetryRestore(bool enabled, bool suppressed, bool ownersKnown, bool allApplied) {
    return enabled && !suppressed && (!ownersKnown || !allApplied);
}
