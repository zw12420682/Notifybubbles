#import <Foundation/Foundation.h>
// State is -1 when unavailable, 0 when false, 1 when true.
static inline BOOL NFBShouldClosePreviousSplit(NSInteger mini, NSInteger transitioning,
                                              NSInteger scene, NSInteger container) {
    return mini == 0 && transitioning == 0 &&
        (scene == 1 || scene == 2) && (container == 1 || container == 2);
}
