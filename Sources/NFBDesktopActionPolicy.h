#pragma once
#include <stdbool.h>

// Animation rule for the desktop/toggle control.
//
// The control shares the top slot of the column, so every layout pass - including
// the 20 Hz ones the watcher and the tick trigger - submitted an animation for it
// with the same frame, alpha and icon size. Re-adding the same curve at 20 Hz
// does nothing visible but keeps the presentation layer busy; and on a pass where
// only the accessibility label changed it also re-committed an identical geometry.
//
// The control now animates only when one of its animated values really changes,
// or when it is appearing from hidden. A pass that only re-brings it to front
// still commits the model values, so nothing can drift.
typedef struct {
    bool appearing;          // visible now and effectively hidden/empty before
    double frameX, frameY, frameWidth, frameHeight;
    double targetX, targetY, targetWidth, targetHeight;
    double alpha, targetAlpha;
    double imageWidth, targetImageWidth;
} NFBDesktopActionInput;

static inline double NFBAbsDiff(double a, double b) {
    double d = a - b;
    return d < 0 ? -d : d;
}

static inline bool NFBDesktopActionNeedsAnimation(NFBDesktopActionInput in) {
    if (in.appearing) return true;
    if (NFBAbsDiff(in.alpha, in.targetAlpha) > 0.001) return true;
    if (NFBAbsDiff(in.frameX, in.targetX) > 0.001) return true;
    if (NFBAbsDiff(in.frameY, in.targetY) > 0.001) return true;
    if (NFBAbsDiff(in.frameWidth, in.targetWidth) > 0.001) return true;
    if (NFBAbsDiff(in.frameHeight, in.targetHeight) > 0.001) return true;
    // The icon side is frame.size.width - 14; compare it in the same units.
    if (NFBAbsDiff(in.imageWidth, in.targetImageWidth) > 0.001) return true;
    return false;
}
