#pragma once
#import <Foundation/Foundation.h>
// Unknown, mini and transitioning windows must never receive this action.
static inline NSInteger NFBExpandedWindowKind(NSInteger mini, NSInteger transitioning,
        NSInteger scene, NSInteger container) {
    if (mini != 0 || transitioning != 0 || scene < 1 || scene > 4 || container < 1 || container > 4) return 0;
    return (scene >= 3 || container >= 3) ? 2 : 1;
}
