#include "../Sources/NFBKeyboardDockPolicy.h"
#include "../Sources/NFBKeyboardSettingsWire.h"
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
 NFBKeyboardSettings decoded={0,0,0,0};
 assert(!NFBKeyboardSettingsDecode(0,&decoded));
 assert(!NFBKeyboardSettingsDecode(UINT64_C(0xFFFFFFFFFFFFFFFF),&decoded));
 for (int flags=0;flags<8;flags++) {
  NFBKeyboardSettings source={flags&1,(flags>>1)&1,(flags>>2)&1,10.25};
  assert(NFBKeyboardSettingsDecode(NFBKeyboardSettingsEncode(source),&decoded));
  assert(source.enabled==decoded.enabled && source.globe==decoded.globe && source.voice==decoded.voice && source.height==decoded.height);
 }
 NFBKeyboardSettings off={0,0,0,34};
 assert(NFBKeyboardSettingsDecode(NFBKeyboardSettingsEncode(off),&decoded) && !decoded.enabled && !decoded.globe && !decoded.voice);
 assert(!NFBKeyboardSettingsDecode(NFB_KEYBOARD_WIRE_MAGIC | 8,&decoded));
 assert(!NFBKeyboardSettingsDecode(NFB_KEYBOARD_WIRE_MAGIC | (UINT64_C(10001)<<16),&decoded));
 NFBKeyboardSettings invalid={1,1,0,NAN};
 assert(NFBKeyboardSettingsDecode(NFBKeyboardSettingsEncode(invalid),&decoded) && !decoded.enabled && decoded.globe);
 puts("PASS: keyboard dock defaults, range, zero, orientation and invalid inputs");
}
