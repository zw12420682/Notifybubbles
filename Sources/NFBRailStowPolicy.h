#pragma once
#include <stdbool.h>
static inline bool NFBStowCanBegin(bool enabled,bool locked,bool home,bool split,bool movie,bool alreadyStowed) {
    return enabled && !locked && home && !split && !movie && !alreadyStowed;
}
