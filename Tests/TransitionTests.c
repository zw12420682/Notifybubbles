#include "NFBTransitionPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(!NFBTransitionStable(10.05, 10));
    assert(NFBTransitionStable(10.13, 10));
    uint64_t epoch = 1, applied = 0;
    assert(NFBTransitionNeedsAction(epoch, applied));
    applied = epoch; /* successful scene action */
    for (int refresh = 0; refresh < 100; refresh++) assert(!NFBTransitionNeedsAction(epoch, applied));
    epoch++; assert(NFBTransitionNeedsAction(epoch, applied));
    applied = epoch; /* manual collapse during pending scene consumes that action */
    assert(!NFBTransitionNeedsAction(epoch, applied));
    for (int enabled = 0; enabled < 2; enabled++)
    for (int reopened = 0; reopened < 2; reopened++)
    for (int protected = 0; protected < 2; protected++) {
        assert(NFBExitStillCurrent(7,7,enabled,reopened,protected) == (enabled && !reopened && !protected));
        assert(!NFBExitStillCurrent(7,8,enabled,reopened,protected));
    }
    assert(NFBExitStillCurrent(7,7,true,false,false)); /* intentional active-app exit */
    assert(!NFBShouldRetryRestore(false,false,false,false));
    assert(!NFBShouldRetryRestore(true,true,false,false));
    assert(NFBShouldRetryRestore(true,false,false,true)); /* late owner registration */
    assert(NFBShouldRetryRestore(true,false,true,false));
    assert(!NFBShouldRetryRestore(true,false,true,true)); /* stop after success / manual collapse */
    puts("PASS: transition consumption, debounce, exit races and bounded restore policy");
    return 0;
}
