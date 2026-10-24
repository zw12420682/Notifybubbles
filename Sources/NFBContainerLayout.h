#import <Foundation/Foundation.h>
#include <math.h>
typedef struct { double favorites; double regular; double gap; } NFBContainerHeights;
static inline NFBContainerHeights NFBFitContainers(double available, double side, double step, NSUInteger favorites, NSUInteger regular) {
    double room = fmax(0, available);
    double a = favorites ? ((favorites - 1) * step + side) : 0;
    double b = regular ? fmin(2 * step + side, (regular - 1) * step + side) : 0;
    double gap = a > 0 && b > 0 ? fmin(9, room) : 0;
    double budget = fmax(0, room - gap);
    double first = fmin(a, b > 0 ? budget / 2 : budget);
    double second = fmin(b, fmax(0, budget - first));
    first = fmin(a, fmax(0, budget - second));
    return (NFBContainerHeights){ first, second, gap };
}
