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
    return 0;
}
