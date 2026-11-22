#include "NFBHomeSwipePolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(NFBHomeSwipeCanBegin(0,-8));
    assert(NFBHomeSwipeCanBegin(2,-4));
    assert(!NFBHomeSwipeCanBegin(8,-2));
    assert(!NFBHomeSwipeCanBegin(0,0));
    assert(!NFBHomeSwipeCanBegin(0,10));
    assert(!NFBHomeSwipeCanBegin(NAN,-10));
    assert(!NFBHomeSwipeCanBegin(0,-INFINITY));
    assert(NFBHomeSwipeCanFinish(0,-80,0,-100));
    assert(NFBHomeSwipeCanFinish(0,-24,0,-600));
    assert(!NFBHomeSwipeCanFinish(0,-23,0,-2000));
    assert(!NFBHomeSwipeCanFinish(0,-30,0,-100));
    assert(!NFBHomeSwipeCanFinish(120,-80,0,-800));
    assert(!NFBHomeSwipeCanFinish(0,-80,0,200));
    assert(!NFBHomeSwipeCanFinish(0,-80,900,-500));
    assert(!NFBHomeSwipeCanFinish(0,-80,NAN,-800));
    assert(!NFBHomeSwipeCanFinish(0,-80,0,-INFINITY));
    assert(NFBHomeSwipeCanCapture(0,0,0,-100,5,100));
    assert(NFBHomeSwipeCanCapture(0,0,0,0,5,100));
    assert(!NFBHomeSwipeCanCapture(0,0,300,-10,5,100));
    assert(!NFBHomeSwipeCanCapture(0,0,0,100,5,100));
    assert(!NFBHomeSwipeCanCapture(0,0,0,0,0,0));
    assert(!NFBHomeSwipeCanCapture(10,0,0,-300,5,100));
    assert(NFBHomeSwipeCanFinish(0,-40,0,-100));
    assert(NFBHomeSwipeCanFinish(0,-50,0,-100));
    assert(!NFBHomeSwipeCanFinish(0,-39,0,-100));
    assert(NFBHomeSwipeCanCapture(15,-5,449.88,-149.96,20,150));
    assert(NFBHomeSwipeCanCapture(-6,-5.6667,-60.1178,-56.778,20.7,56.8));
    assert(NFBHomeSwipeCanCapture(5,-5,85.853,-85.853,20,85.9));
    assert(NFBHomeSwipeCanCapture(10.333,-6,95.44,-55.417,22,55.4));
    assert(!NFBHomeSwipeCanCapture(40,-2,700,-25,20,25));
    assert(!NFBHomeSwipeCanCapture(15,5,449,150,20,-150));
    assert(!NFBHomeSwipeCanCapture(15,-5,449,-150,20,-150));
    puts("Home swipe direction/completion boundaries PASS");
    return 0;
}
