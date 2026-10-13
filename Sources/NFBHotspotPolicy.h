#pragma once
#include <stdbool.h>
#include <math.h>
typedef struct { double idleSince; bool tracking; bool submitted; } NFBHotspotPolicy;
static inline void NFBHotspotReset(NFBHotspotPolicy *policy) { policy->idleSince=0; policy->tracking=false; policy->submitted=false; }
static inline bool NFBHotspotShouldClose(NFBHotspotPolicy *policy, bool configured, int state, long long clients, double now, double seconds) {
    if (!configured || state != 1 || clients != 0 || !isfinite(now) || !isfinite(seconds) || seconds <= 0) { NFBHotspotReset(policy); return false; }
    if (!policy->tracking || now < policy->idleSince) { policy->idleSince=now; policy->tracking=true; policy->submitted=false; }
    return !policy->submitted && now-policy->idleSince >= seconds;
}
