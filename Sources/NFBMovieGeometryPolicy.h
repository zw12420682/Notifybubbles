#pragma once
#include <stdbool.h>
#include <math.h>
#define NFBMoviePortraitScale 0.86
// Native Open portrait content fits the usual 9:16 footprint at 0.86.
static inline double NFBMoviePaneHeight(double aw,double ah) {
    return NFBMoviePortraitScale*fmin(ah,aw*16.0/9.0);
}

static inline bool NFBPiPStableEnough(double age) {
    return isfinite(age) && age>=0.45;
}
static inline bool NFBPiPCanRetryReset(bool retried,double age) {
    return !retried && isfinite(age) && age>=0 && age<=2.0;
}
static inline double NFBPiPFitScale(double width,double height,double roomWidth,double roomHeight) {
    if (!isfinite(width)||!isfinite(height)||!isfinite(roomWidth)||!isfinite(roomHeight)||
        width<=0||height<=0||roomWidth<=0||roomHeight<=0) return 0;
    return fmin(1,fmin(roomWidth/width,roomHeight/height));
}
static inline bool NFBMovieLowerGeometryValid(double x,double y,double w,double h,
    double ax,double ay,double aw,double ah) {
    return isfinite(x)&&isfinite(y)&&isfinite(w)&&isfinite(h)&&
        isfinite(ax)&&isfinite(ay)&&isfinite(aw)&&isfinite(ah)&&
        w>=120 && h>=180 && aw>0 && ah>0 &&
        x>=ax-2 && x+w<=ax+aw+2 && y-ay>=32 && y+h<=ay+ah+2;
}
