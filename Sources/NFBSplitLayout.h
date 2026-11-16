#pragma once
#include <stdbool.h>
#include <math.h>
// Engine-independent units: points in one explicit parent coordinate space.
// No UIWindow, scene selector, preference access, or animation side effect.
typedef struct { double a,b,c,d; } NFBSplitBasis;
typedef struct { double scale,x,y,width,height; bool valid; } NFBSplitMovieTarget;
static inline NFBSplitMovieTarget NFBSplitPlanMovie(double areaX,double areaY,double areaW,double areaH,
        double lowerY,double lowerW,double lowerH,double lowerBottom,
        double boundsW,double boundsH,NFBSplitBasis basis,double gap) {
    NFBSplitMovieTarget t={0};
    double v[]={areaX,areaY,areaW,areaH,lowerY,lowerW,lowerH,lowerBottom,boundsW,boundsH,basis.a,basis.b,basis.c,basis.d,gap};
    for (unsigned i=0;i<sizeof(v)/sizeof(v[0]);i++) if (!isfinite(v[i])) return t;
    if (areaW<=0 || areaH<=areaW || boundsW<1 || boundsH<1 || lowerW<120 || lowerH<180 ||
        lowerY-areaY<32 || lowerBottom>areaY+areaH+2 || gap<0) return t;
    double w=fabs(basis.a)*boundsW+fabs(basis.c)*boundsH;
    double h=fabs(basis.b)*boundsW+fabs(basis.d)*boundsH;
    if (w<1 || h<1) return t;
    t.scale=fmin((lowerY-areaY-gap)/h,areaW/w);
    if (t.scale<=0 || !isfinite(t.scale)) return t;
    t.width=w*t.scale;t.height=h*t.scale;
    t.x=areaX+areaW/2;t.y=lowerY-gap-t.height/2;t.valid=true;
    return t;
}
