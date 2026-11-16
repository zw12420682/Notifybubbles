#include "NFBSplitObservation.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 NFBSplitObservationTracker t={0};
 assert(NFBSplitRetainMovie(&t,false,true,NFBSplitObservationPresent));
 assert(NFBSplitRetainMovie(&t,true,true,NFBSplitObservationUnknown));
 assert(NFBSplitRetainMovie(&t,true,true,NFBSplitObservationAbsent));
 assert(!NFBSplitRetainMovie(&t,true,true,NFBSplitObservationAbsent));
 assert(NFBSplitRetainMovie(&t,false,true,NFBSplitObservationPresent));
 assert(!NFBSplitRetainMovie(&t,true,false,NFBSplitObservationUnknown));
 assert(!NFBSplitRetainMovie(&t,false,true,NFBSplitObservationUnknown));
 puts("PASS: bounded unknown/absence and immediate disabled cleanup");
}
