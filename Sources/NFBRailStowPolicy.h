#pragma once
#include <stdbool.h>
static inline bool NFBStowCanBegin(bool enabled,bool locked,bool home,bool split,bool movie,bool alreadyStowed) {
    (void)home; // Both the home screen and fullscreen apps may enter stow.
    return enabled && !locked && !split && !movie && !alreadyStowed;
}
