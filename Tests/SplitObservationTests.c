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
 assert(!NFBSplitRetainMovieWithClosure(&t,true,true,NFBSplitObservationAbsent,true));
 assert(t.missing==0);
 assert(NFBSplitRetainMovieWithClosure(&t,true,true,NFBSplitObservationUnknown,false));
 assert(NFBSplitRetainMovieWithClosure(&t,true,true,NFBSplitObservationPresent,true));
 assert(!NFBSplitRetainMovieWithClosure(&t,true,false,NFBSplitObservationUnknown,false));
 puts("PASS: bounded unknown/absence, explicit close fast path, replacement survives, disabled cleanup");
}
