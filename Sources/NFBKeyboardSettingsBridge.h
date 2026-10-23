#pragma once
#import <Foundation/Foundation.h>
#import <notify.h>
#import "NFBKeyboardSettingsWire.h"
#define NFB_KEYBOARD_SETTINGS_CHANNEL "local.notifybubbles.keyboard.settings.v1"
static inline int NFBKeyboardSettingsToken(void) {
    static int token=-1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int registered=-1;
        if (notify_register_check(NFB_KEYBOARD_SETTINGS_CHANNEL,&registered)==NOTIFY_STATUS_OK) token=registered;
    });
    return token;
}
static inline BOOL NFBKeyboardSettingsReceive(NFBKeyboardSettings *settings) {
    int token=NFBKeyboardSettingsToken(); uint64_t value=0;
    return token>=0 && notify_get_state(token,&value)==NOTIFY_STATUS_OK && NFBKeyboardSettingsDecode(value,settings);
}
static inline id NFBKeyboardPreference(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,CFSTR("local.notifybubbles")));
}
// Only the Settings preference pane and SpringBoard-side keyboard module call
// this publisher. Sandboxed apps consume the snapshot; they never publish nil
// preferences back over the real settings.
static inline BOOL NFBKeyboardSettingsPublish(void) {
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    id enabled=NFBKeyboardPreference(@"KeyboardBottomEnabled");
    id height=NFBKeyboardPreference(@"KeyboardBottomHeight");
    id globe=NFBKeyboardPreference(@"KeyboardHideGlobe");
    id voice=NFBKeyboardPreference(@"KeyboardHideVoice");
    NFBKeyboardSettings settings={
        [enabled isKindOfClass:NSNumber.class] && [enabled boolValue],
        [globe isKindOfClass:NSNumber.class] && [globe boolValue],
        [voice isKindOfClass:NSNumber.class] && [voice boolValue],
        [height isKindOfClass:NSNumber.class] ? [height doubleValue] : 34.0};
    int token=NFBKeyboardSettingsToken(); if (token<0) return NO;
    uint64_t value=NFBKeyboardSettingsEncode(settings),previous=0;
    if (notify_get_state(token,&previous)==NOTIFY_STATUS_OK && value==previous) return YES;
    if (notify_set_state(token,value)!=NOTIFY_STATUS_OK) return NO;
    return notify_post(NFB_KEYBOARD_SETTINGS_CHANNEL)==NOTIFY_STATUS_OK;
}
