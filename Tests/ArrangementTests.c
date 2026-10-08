#include "NFBArrangement.h"
#include <assert.h>
int main(void){
 NFBTile invalid[]={{0,10,0,0}};assert(NFBArrangeMixed(invalid,1,0,0,844)==0);
 NFBTile onlyLandscape[]={{300,200,0,0}};assert(NFBArrangeMixed(onlyLandscape,1,0,1,844)==1);assert(onlyLandscape[0].y==0);
 NFBTile mixed[]={{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(mixed,2,0,1,844);assert(mixed[0].y==0);assert(fabs(mixed[1].y+mixed[1].height-844)<0.001);assert(mixed[0].height<=mixed[1].y);
 NFBTile multi[]={{300,150,0,0},{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(multi,3,0,2,844);assert(multi[0].y==0);assert(multi[1].y>=multi[0].height);assert(multi[2].y>=multi[1].y+multi[1].height);
 NFBTile slider[]={{300,200,0,0}};NFBArrangeMixed(slider,1,0,1,844);NFBPositionLandscape(slider,1,0,1,844,0.5);assert(fabs(slider[0].y-322)<0.001);
 NFBTile blocked[]={{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(blocked,2,0,1,844);double portraitY=blocked[1].y;NFBPositionLandscape(blocked,2,0,1,844,2);assert(fabs(blocked[0].y+blocked[0].height-844)<0.001);assert(blocked[1].y==portraitY);
 NFBTile mixedPos[]={{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(mixedPos,2,0,1,844);NFBPositionLandscape(mixedPos,2,0,1,844,0.5);assert(fabs(mixedPos[0].y-347)<0.001);assert(fabs(mixedPos[1].y-494)<0.001);
 NFBTile top[]={{300,200,0,0}};NFBArrangeMixed(top,1,0,1,844);NFBPositionLandscape(top,1,0,1,844,NAN);assert(top[0].y==0);
 // Mini row: horizontal at the top, left to right.
 NFBTile miniOnly[]={{200,80,0,0},{250,350,0,0}};NFBArrangeMixed(miniOnly,2,1,0,844);assert(miniOnly[0].y==0);assert(fabs(miniOnly[1].y+miniOnly[1].height-844)<0.001);
 NFBTile miniRow[]={{200,80,0,0},{160,90,0,0}};NFBArrangeMixed(miniRow,2,2,0,844);assert(miniRow[0].x==0);assert(miniRow[1].x>=miniRow[0].width);assert(miniRow[0].y==0);assert(miniRow[1].y==0);
 NFBTile miniTop[]={{200,80,0,0},{300,100,0,0},{250,350,0,0}};NFBArrangeMixed(miniTop,3,1,1,844);assert(miniTop[0].y==0);assert(miniTop[1].y>=miniTop[0].height);assert(fabs(miniTop[2].y+miniTop[2].height-844)<0.001);
 return 0;}
