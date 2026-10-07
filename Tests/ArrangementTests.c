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
 return 0;}
