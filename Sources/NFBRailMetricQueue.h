#pragma once
#include <stdbool.h>
#include "NFBRailState.h"

// The newest geometry waiting for the debounced write.
//
// The store used to keep only a "queued" flag and hand the *captured* metric to
// the delayed block. A split lays out at display rate, so A arrives, then B, then
// C inside the same debounce window: the block still wrote A and C was lost until
// the next change - the exact bug this queue fixes. The queue keeps the latest
// pending value, so the write that finally runs stores C.
//
// Rules (shared by NFBRailStateStore and its regression test):
//   * unusable geometry is ignored, and it never cancels a pending valid write;
//   * geometry equal to the committed record needs no write;
//   * equal to what is already pending needs no new clock.
typedef struct {
    bool pending;                // a write is scheduled
    bool pendingValid;
    NFBRailMetric pendingMetric; // newest geometry still waiting
    bool committedValid;
    NFBRailMetric committed;     // what is on disk
} NFBRailMetricQueue;

// After the store loads the record from disk.
static inline NFBRailMetricQueue NFBRailMetricQueueLoaded(NFBRailMetric stored, bool storedValid) {
    NFBRailMetricQueue queue;
    queue.pending = false;
    queue.pendingValid = false;
    queue.pendingMetric = NFBRailMetricNoRecord();
    queue.committedValid = storedValid;
    queue.committed = storedValid ? stored : NFBRailMetricNoRecord();
    return queue;
}

// Offers a newly measured geometry. Returns true when the caller has to start the
// debounce clock (nothing was scheduled before); when a clock is already running
// the newest value is remembered and the existing clock writes it. False means
// "nothing to do at all".
static inline bool NFBRailMetricQueueOffer(NFBRailMetricQueue *queue, NFBRailMetric metric) {
    if (!NFBRailMetricUsable(metric, metric.screenWidth)) return false;
    if (queue->committedValid && NFBRailMetricEqual(queue->committed, metric)) return false;
    if (queue->pending && queue->pendingValid && NFBRailMetricEqual(queue->pendingMetric, metric)) return false;
    queue->pendingMetric = metric;
    queue->pendingValid = true;
    if (queue->pending) return false;
    queue->pending = true;
    return true;
}

// The debounce fired: hand back the newest pending metric and clear the clock.
// Returns false when nothing usable is pending (e.g. every offer was invalid).
// The clock is cleared before the write runs, so a change offered from inside it
// starts a fresh clock instead of reusing the one that just ran.
static inline bool NFBRailMetricQueueDrain(NFBRailMetricQueue *queue, NFBRailMetric *out) {
    queue->pending = false;
    if (!queue->pendingValid) return false;
    queue->pendingValid = false;
    *out = queue->pendingMetric;
    return true;
}

// A write was committed: the record is now on disk.
static inline void NFBRailMetricQueueCommitted(NFBRailMetricQueue *queue, NFBRailMetric metric) {
    queue->committed = metric;
    queue->committedValid = true;
}
