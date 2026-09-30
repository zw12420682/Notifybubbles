#import <Foundation/Foundation.h>
#include <stdint.h>
static inline NSString *NFBBackName(NSString *app) {
    return [@"local.notifybubbles.back." stringByAppendingString:app];
}
static inline uint64_t NFBBackTime(void) {
    return (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000);
}
static inline BOOL NFBBackFresh(uint64_t request, uint64_t now) {
    return request > 0 && request <= now && now - request < 1500;
}
// The target app's own diagnostics land in its sandbox (a different log file the
// user cannot easily reach), so the WHY of a failed back is folded into the reply
// state instead: reply = (request << NFBBackStatusShift) | status. The requester
// (SpringBoard) can then log and surface the exact reason.
typedef NS_ENUM(uint8_t, NFBBackStatus) {
    NFBBackStatusPerformed = 0,     // A back action actually ran.
    NFBBackStatusNoWindow = 1,      // No usable window in the app process.
    NFBBackStatusNoBackAction = 2,  // Windows found, but no nav stack / web history.
    NFBBackStatusCustomBackItem = 3,// Custom left button or hidesBackButton: do not guess.
    NFBBackStatusTransitioning = 4, // Transition in flight or an alert is up.
    NFBBackStatusException = 5,     // The back attempt threw.
};
enum { NFBBackStatusShift = 4 };
