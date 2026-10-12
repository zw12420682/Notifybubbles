#include "NFBOpenConsolePolicy.h"
#include "NFBTransitionPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(!NFBTransitionStable(10.05, 10));
    assert(NFBTransitionStable(10.13, 10));
    for (int enabled = 0; enabled < 2; enabled++)
    for (int split = 0; split < 2; split++)
    for (int keyboard = 0; keyboard < 2; keyboard++)
        assert(NFBEdgeShouldHide(enabled,split,keyboard) == (enabled && (split || keyboard)));
    assert(NFBRestoreAfterKeyboard(true,true,false,true));
    assert(!NFBRestoreAfterKeyboard(true,true,false,false)); /* scene changed while typing */
    assert(!NFBRestoreAfterKeyboard(true,true,true,true)); /* split bubbles still visible */
    assert(!NFBRestoreAfterKeyboard(true,false,false,true));
    uint8_t unknown[16] = {0};
    assert(!NFBConsoleTargetForImage(0x0100000c,0,unknown));
    const uint8_t uuid0[16] = {0x6f,0xea,0xd8,0x04,0xf1,0xc9,0x33,0x60,0xb3,0x5e,0xed,0xeb,0x38,0x63,0x20,0xfb};
    const uint8_t uuid2[16] = {0x3a,0x86,0xa9,0x83,0xe7,0x81,0x3d,0x47,0xa5,0x99,0xa8,0x14,0x88,0xb1,0xe9,0x07};
    const NFBConsoleTarget *console = NFBConsoleTargetForImage(0x0100000c,0,uuid0);
    assert(console && console->address == 0x7aa24);
    assert(NFBConsoleTargetForImage(0x0100000c,0x80000002,uuid2));
    assert(!NFBConsoleTargetForImage(0x0100000c,2,uuid0));
    assert(!NFBConsoleTargetForImage(7,0,uuid0));
    uint8_t code[20]; memcpy(code,console->code,20);
    assert(NFBConsoleCodeMatches(console,code));
    code[19] ^= 1; assert(!NFBConsoleCodeMatches(console,code));
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
    puts("PASS: transition consumption, debounce, exit races, keyboard restore and console binary guards");
    return 0;
}
