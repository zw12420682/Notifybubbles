#import <Foundation/Foundation.h>
// Main-thread only. Unknown/unavailable settings preserve existing visibility.
BOOL NFBSystemNotificationsAllowed(NSString *app, void (^changed)(void));
