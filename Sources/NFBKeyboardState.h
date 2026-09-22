#import <Foundation/Foundation.h>
#include <notify.h>

// SpringBoard publishes the setting so sandboxed keyboard/app processes do not
// depend on reading another process's CFPreferences domain. 0 means unpublished.
#define NFBKeyboardStateName "local.notifybubbles.keyboard-state"
static inline void NFBPublishKeyboardState(BOOL enabled) {
    static int token = -1;
    if (token == -1 && notify_register_check(NFBKeyboardStateName, &token) != NOTIFY_STATUS_OK) return;
    if (notify_set_state(token, enabled ? 2 : 1) == NOTIFY_STATUS_OK)
        notify_post(NFBKeyboardStateName);
}
