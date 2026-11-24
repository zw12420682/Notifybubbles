#include "NFBMovieGeometryPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    if (fabs(NFBPiPFitScale(368,276,382,244)-244.0/276)>0.00001 ||
        NFBPiPFitScale(160,90,382,244)!=1 || NFBPiPFitScale(368,276,382,-1)!=0) return 1;
    if (fabs(NFBMoviePaneHeight(390,844)-596.2666666667)>0.001) return 1;
 assert(NFBMovieLowerGeometryValid(0,248.02,335.4,595.98,0,0,390,844));
 assert(NFBMovieLowerGeometryValid(0,118.16,335.4,725.84,0,0,390,844));
 assert(!NFBMovieLowerGeometryValid(181.584,-23.8392,26.832,47.6784,0,0,390,844));
 assert(!NFBMovieLowerGeometryValid(0,0,335.4,595.98,0,0,390,844));
 assert(!NFBMovieLowerGeometryValid(400,248,335,596,0,0,390,844));
 assert(!NFBMovieLowerGeometryValid(0,248,NAN,596,0,0,390,844));
 assert(!NFBMovieLowerGeometryValid(0,248,335,INFINITY,0,0,390,844));
 puts("Movie lower geometry device regression PASS");
 return 0;
}
