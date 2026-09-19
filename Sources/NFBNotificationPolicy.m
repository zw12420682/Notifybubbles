#import "NFBNotificationPolicy.h"
#import <UserNotifications/UserNotifications.h>
@interface UNUserNotificationCenter (NFBSystemSettings)
- (instancetype)initWithBundleIdentifier:(NSString *)identifier;
@end

BOOL NFBSystemNotificationsAllowed(NSString *app, void (^changed)(void)) {
    static NSMutableDictionary *allowed, *queried, *centers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSMutableDictionary dictionary];
        queried = [NSMutableDictionary dictionary];
        centers = [NSMutableDictionary dictionary];
    });
    NSCAssert(NSThread.isMainThread, @"Notification policy is main-thread confined");
    if (!app.length) return YES;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!queried[app] || now - [queried[app] doubleValue] >= 5) {
        NSNumber *generation = @(now);
        queried[app] = generation;
        @try {
            if ([UNUserNotificationCenter instancesRespondToSelector:@selector(initWithBundleIdentifier:)]) {
                UNUserNotificationCenter *center = [[UNUserNotificationCenter alloc] initWithBundleIdentifier:app];
                if (center) {
                    centers[app] = center;
                    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (![queried[app] isEqual:generation]) return;
                            [centers removeObjectForKey:app];
                            if (!settings) return;
                            // Only "Allow Notifications" denied hides the notification source.
                            BOOL next = settings.authorizationStatus != UNAuthorizationStatusDenied;
                            BOOL previous = allowed[app] ? [allowed[app] boolValue] : YES;
                            allowed[app] = @(next);
                            if (next != previous && changed) changed();
                        });
                    }];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        if ([queried[app] isEqual:generation]) [centers removeObjectForKey:app];
                    });
                }
            }
        } @catch (__unused NSException *e) { [centers removeObjectForKey:app]; }
    }
    return allowed[app] ? [allowed[app] boolValue] : YES;
}
