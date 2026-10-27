#pragma once
// The platform chooses the geometry backend in this test-only header.
// Apple uses the SDK types, imported before any test/plan header is parsed;
// other hosts use the small portable geometry subset below. No production
// UIKit header includes this shim.
#if defined(__APPLE__)
#include <CoreGraphics/CoreGraphics.h>
#else

#include <stdbool.h>

// Plain structs, same layout as CoreGraphics' (two doubles per point/size).
struct CGPoint { double x, y; };
struct CGSize { double width, height; };
struct CGRect { struct CGPoint origin; struct CGSize size; };

typedef struct CGPoint CGPoint;
typedef struct CGSize CGSize;
typedef struct CGRect CGRect;

static inline double CGRectGetMinX(CGRect r) { return r.origin.x; }
static inline double CGRectGetMinY(CGRect r) { return r.origin.y; }
static inline double CGRectGetMaxX(CGRect r) { return r.origin.x + r.size.width; }
static inline double CGRectGetMaxY(CGRect r) { return r.origin.y + r.size.height; }
static inline double CGRectGetMidX(CGRect r) { return r.origin.x + r.size.width / 2; }
static inline double CGRectGetMidY(CGRect r) { return r.origin.y + r.size.height / 2; }
static inline double CGRectGetWidth(CGRect r) { return r.size.width; }
static inline double CGRectGetHeight(CGRect r) { return r.size.height; }
static inline CGRect CGRectMake(double x, double y, double w, double h) {
    CGRect r; r.origin.x = x; r.origin.y = y; r.size.width = w; r.size.height = h; return r;
}
static inline CGRect CGRectUnion(CGRect a, CGRect b) {
    double x0 = CGRectGetMinX(a) < CGRectGetMinX(b) ? CGRectGetMinX(a) : CGRectGetMinX(b);
    double y0 = CGRectGetMinY(a) < CGRectGetMinY(b) ? CGRectGetMinY(a) : CGRectGetMinY(b);
    double x1 = CGRectGetMaxX(a) > CGRectGetMaxX(b) ? CGRectGetMaxX(a) : CGRectGetMaxX(b);
    double y1 = CGRectGetMaxY(a) > CGRectGetMaxY(b) ? CGRectGetMaxY(a) : CGRectGetMaxY(b);
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}
static inline bool CGRectIsEmpty(CGRect r) { return r.size.width == 0 || r.size.height == 0; }
static inline bool CGRectIsNull(CGRect r) {
    return r.origin.x == 0.0 / 0.0 && r.origin.y == 0.0 / 0.0 && r.size.width == 0.0 && r.size.height == 0.0;
}
static inline CGPoint CGPointMake(double x, double y) { CGPoint p; p.x = x; p.y = y; return p; }
static inline CGSize CGSizeMake(double w, double h) { CGSize s; s.width = w; s.height = h; return s; }

// Named rectangles with CoreGraphics' shapes: CGRectZero is all zero, CGRectNull
// keeps an infinite origin + zero size so CGRectIsNull above recognises it. These
// are macros only where no CoreGraphics header declares the real constants.
#define CGRectZero CGRectMake(0, 0, 0, 0)
#define CGRectNull CGRectMake(__builtin_inf(), __builtin_inf(), 0, 0)

#endif  // !__APPLE__
