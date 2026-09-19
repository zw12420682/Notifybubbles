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
