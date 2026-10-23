#include "../Sources/NFBKeyboardDockPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 assert(NFBKeyboardDockBottom(34,0,0,1)==34);
 assert(NFBKeyboardDockBottom(34,1,0,1)==0);
 assert(NFBKeyboardDockBottom(34,1,55,1)==55);
 assert(NFBKeyboardDockBottom(34,1,150,1)==100);
 assert(NFBKeyboardDockBottom(34,1,-5,1)==0);
 assert(NFBKeyboardDockBottom(21,1,55,0)==21);
 assert(NFBKeyboardDockBottom(0,1,55,1)==0);
 assert(NFBKeyboardDockBottom(34,1,NAN,1)==34);
 assert(NFBKeyboardDockBottom(34,1,INFINITY,1)==34);
 puts("PASS: keyboard dock defaults, range, zero, orientation and invalid inputs");
}
