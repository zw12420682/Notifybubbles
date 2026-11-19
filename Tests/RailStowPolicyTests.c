#include "NFBRailStowPolicy.h"
#include <assert.h>
int main(void) {
    assert(NFBStowCanBegin(true,false,true,false,false,false));
    assert(!NFBStowCanBegin(true,false,true,true,false,false));
    assert(!NFBStowCanBegin(true,false,true,false,true,false));
    assert(!NFBStowCanBegin(false,false,true,false,false,false));
    assert(!NFBStowCanBegin(true,true,true,false,false,false));
    assert(!NFBStowCanBegin(true,false,false,false,false,false));
    assert(!NFBStowCanBegin(true,false,true,false,false,true));
    assert(NFBStowMustRestore(false,false,false));
    assert(NFBStowMustRestore(true,true,false));
    assert(NFBStowMustRestore(true,false,true));
    assert(!NFBStowMustRestore(true,false,false));
    return 0;
}
