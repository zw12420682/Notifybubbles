#pragma once
#include <stdint.h>
#include <math.h>
typedef struct { int enabled,globe,voice; double height; } NFBKeyboardSettings;
#define NFB_KEYBOARD_WIRE_MAGIC UINT64_C(0x4E46420100000000)
static inline uint64_t NFBKeyboardSettingsEncode(NFBKeyboardSettings settings) {
    int valid=isfinite(settings.height);
    double height=valid ? fmin(100.0,fmax(0.0,settings.height)) : 34.0;
    uint64_t units=(uint64_t)(height*100.0+0.5);
    return NFB_KEYBOARD_WIRE_MAGIC | (units<<16) | ((settings.enabled && valid) ? 1 : 0) |
        (settings.globe ? 2 : 0) | (settings.voice ? 4 : 0);
}
static inline int NFBKeyboardSettingsDecode(uint64_t value,NFBKeyboardSettings *settings) {
    if (!settings || (value & UINT64_C(0xFFFFFFFF00000000))!=NFB_KEYBOARD_WIRE_MAGIC ||
        (value & UINT64_C(0xFFF8)) || ((value>>16)&UINT64_C(0xFFFF))>10000) return 0;
    settings->enabled=(value&1)!=0; settings->globe=(value&2)!=0; settings->voice=(value&4)!=0;
    settings->height=(double)((value>>16)&UINT64_C(0xFFFF))/100.0;
    return 1;
}
