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
 NFBTile onlyLandscape[]={{300,200,0,0}};assert(NFBArrangeGroups(onlyLandscape,1,1,390,844)==1);assert(onlyLandscape[0].y==0);
 NFBTile mixed[]={{300,150,0,0},{250,350,0,0}};NFBArrangeGroups(mixed,2,1,390,844);assert(mixed[0].y==0);assert(fabs(mixed[1].y+mixed[1].height-844)<0.001);assert(mixed[0].height<=mixed[1].y);
 NFBTile multi[]={{300,150,0,0},{300,150,0,0},{250,350,0,0}};NFBArrangeGroups(multi,3,2,390,844);assert(multi[0].y==0);assert(multi[1].y>=multi[0].height);assert(multi[2].y>=multi[1].y+multi[1].height);
 NFBTile overflow[]={{800,400,0,0},{335,725,0,0}};double f=NFBArrangeGroups(overflow,2,1,390,844);assert(f<1);assert(overflow[0].y==0);assert(overflow[1].y>=overflow[0].height-0.001);
 return 0;}
