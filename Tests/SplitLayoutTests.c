#include "NFBSplitLayout.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 NFBSplitBasis b={1,0,0,1};
 double tops[]={248.02,151,118.16};
 for(unsigned i=0;i<3;i++) {
  NFBSplitMovieTarget t=NFBSplitPlanMovie(0,0,390,844,tops[i],335.4,595.98,844,390,219.5,b,4);
  assert(t.valid);
  assert(fabs((tops[i]-(t.y+t.height/2))-4)<1e-6);
  assert(t.width<=390.000001);
  assert(fabs(t.width/t.height-390/219.5)<1e-6);
 }
 assert(!NFBSplitPlanMovie(0,0,390,844,2,335,596,844,390,219,b,4).valid);
 assert(!NFBSplitPlanMovie(0,0,844,390,151,335,596,844,390,219,b,4).valid);
 assert(!NFBSplitPlanMovie(0,0,390,844,151,1,1,844,390,219,b,4).valid);
 assert(!NFBSplitPlanMovie(0,0,390,844,NAN,335,596,844,390,219,b,4).valid);
 puts("PASS: independent movie geometry, keyboard sizes, four point gap and transient rejection");
 return 0;
}
