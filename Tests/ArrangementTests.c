#include "NFBArrangement.h"
#include <assert.h>
static void check(NFBTile *t,size_t n,double w,double h) {
 double f=NFBArrange(t,n,w,h); assert(f>0 && f<=1);
 for(size_t i=0;i<n;i++){assert(t[i].x>=0 && t[i].y>=-0.001);assert(t[i].width<=w+0.001);assert(t[i].y+t[i].height<=h+0.001);if(i)assert(t[i].y>=t[i-1].y+t[i-1].height);}
}
int main(void){
 NFBTile fits[]={{200,100,0,0},{200,300,0,0}};check(fits,2,390,844);assert(fits[0].width==200);assert(fabs(fits[1].y+fits[1].height-844)<0.001);
 NFBTile tall[]={{380,300,0,0},{335,725,0,0},{100,150,0,0}};check(tall,3,390,844);assert(tall[0].width<380);
 NFBTile wide[]={{844,390,0,0},{335,725,0,0}};check(wide,2,390,844);
 NFBTile many[100];for(int i=0;i<100;i++)many[i]=(NFBTile){300,600,0,0};check(many,100,390,844);
 NFBTile invalid[]={{0,10,0,0}};assert(NFBArrange(invalid,1,390,844)==0);assert(NFBArrange(0,0,390,844)==1);
 // No mini row (rowCount=0): behaves like the old landscape-top arrangement.
 NFBTile onlyLandscape[]={{300,200,0,0}};assert(NFBArrangeMixed(onlyLandscape,1,0,1,390,844)==1);assert(onlyLandscape[0].y==0);
 NFBTile mixed[]={{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(mixed,2,0,1,390,844);assert(mixed[0].y==0);assert(fabs(mixed[1].y+mixed[1].height-844)<0.001);assert(mixed[0].height<=mixed[1].y);
 NFBTile multi[]={{300,150,0,0},{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(multi,3,0,2,390,844);assert(multi[0].y==0);assert(multi[1].y>=multi[0].height);assert(multi[2].y>=multi[1].y+multi[1].height);
 NFBTile overflow[]={{800,400,0,0},{335,725,0,0}};double f=NFBArrangeMixed(overflow,2,0,1,390,844);assert(f<1);assert(overflow[0].y==0);assert(overflow[1].y>=overflow[0].height-0.001);
 // Slider positions the vertical top group through the space below the row.
 NFBTile slider[]={{300,200,0,0}};NFBArrangeMixed(slider,1,0,1,390,844);NFBPositionLandscape(slider,1,0,1,844,0.5);assert(fabs(slider[0].y-322)<0.001);
 NFBTile blocked[]={{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(blocked,2,0,1,390,844);double portraitY=blocked[1].y;NFBPositionLandscape(blocked,2,0,1,844,2);assert(fabs(blocked[0].y+blocked[0].height-844)<0.001);assert(blocked[1].y==portraitY);
 NFBTile mixedPos[]={{300,150,0,0},{250,350,0,0}};NFBArrangeMixed(mixedPos,2,0,1,390,844);NFBPositionLandscape(mixedPos,2,0,1,844,0.5);assert(fabs(mixedPos[0].y-347)<0.001);assert(fabs(mixedPos[1].y-494)<0.001);
 NFBTile top[]={{300,200,0,0}};NFBArrangeMixed(top,1,0,1,390,844);NFBPositionLandscape(top,1,0,1,844,NAN);assert(top[0].y==0);
 // Mini row: horizontal at the top, left to right.
 NFBTile miniOnly[]={{200,80,0,0},{250,350,0,0}};NFBArrangeMixed(miniOnly,2,1,0,390,844);assert(miniOnly[0].y==0);assert(fabs(miniOnly[1].y+miniOnly[1].height-844)<0.001);
 NFBTile miniRow[]={{200,80,0,0},{160,90,0,0}};NFBArrangeMixed(miniRow,2,2,0,390,844);assert(miniRow[0].x==0);assert(miniRow[1].x>=miniRow[0].width);assert(miniRow[0].y==0);assert(miniRow[1].y==0);
 NFBTile miniTop[]={{200,80,0,0},{300,100,0,0},{250,350,0,0}};NFBArrangeMixed(miniTop,3,1,1,390,844);assert(miniTop[0].y==0);assert(miniTop[1].y>=miniTop[0].height);assert(fabs(miniTop[2].y+miniTop[2].height-844)<0.001);
 return 0;}
