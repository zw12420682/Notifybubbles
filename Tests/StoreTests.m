#import <Foundation/Foundation.h>
#import "NFBStore.h"
#include <stdlib.h>

static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NFBStore *store = [NFBStore new];
        NSObject *destination = [NSObject new];
        NSObject *first = [NSObject new];
        NSObject *replacement = [NSObject new];
        Check(store.count == 0 && store.appIDs.count == 0, @"No phantom bubbles on startup");
        [store putApp:@"chat" notification:@"1" request:first destination:destination];
        [store putApp:@"chat" notification:@"1" request:replacement destination:destination];
        Check(store.count == 1, @"Repeated deliveries are deduplicated");
        Check([store latestForApp:@"chat"].request == replacement, @"Updated action replaces old request");
        [store putApp:@"mail" notification:@"1" request:first destination:destination];
        Check(store.count == 2, @"Identical IDs from different apps are distinct");
        [store putApp:@"chat" notification:@"2" request:first destination:destination];
        Check([store.appIDs isEqual:@[@"chat", @"mail"]], @"Most recent app is first");
        [store removeApp:@"chat" notification:@"2"];
        Check([[store latestForApp:@"chat"].notificationID isEqual:@"1"], @"Withdrawal restores previous actionable notification");
        [store removeApp:@"chat" notification:@"missing"];
        Check(store.count == 2, @"Unrelated withdrawal is harmless");
        [store clear];
        Check(store.count == 0 && ![store latestForApp:@"mail"], @"Tap clearing removes every app");
        [store putApp:@"chat" notification:@"new" request:first destination:destination];
        Check(store.count == 1, @"A new message after clearing creates a fresh bubble");
        [store putApp:@"" notification:@"bad" request:first destination:destination];
        [store putApp:@"mail" notification:@"bad" request:nil destination:destination];
        Check(store.count == 1, @"Invalid requests cannot create empty bubbles");
        [store removeApp:@"chat"];
        Check(store.count == 0, @"Section removal clears only that app");
        for (NSUInteger i = 0; i < 600; i++)
            [store putApp:@"chat" notification:[NSString stringWithFormat:@"%lu", (unsigned long)i]
                request:first destination:destination];
        Check(store.count == 512, @"Retained requests are bounded");
        Check([[store latestForApp:@"chat"].notificationID isEqual:@"599"], @"Eviction preserves latest action");
        NSLog(@"PASS: 13 notification-state checks");
    }
    return 0;
}
