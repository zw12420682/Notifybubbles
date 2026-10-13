#pragma once
#include <math.h>
// Preserve native desktop bounds and uniformly scale its complete coordinate space.
static inline double NFBDesktopScale(double width, double height, double availableWidth, double availableHeight) {
    if (!isfinite(width) || !isfinite(height) || !isfinite(availableWidth) || !isfinite(availableHeight) ||
        width <= 0 || height <= 0 || availableWidth <= 0 || availableHeight <= 0) return 0;
    double scale = fmin(availableWidth / width, availableHeight / height);
    return isfinite(scale) && scale > 0 ? scale : 0;
}
