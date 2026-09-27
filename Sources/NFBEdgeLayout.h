#import <Foundation/Foundation.h>
// Keep every app. The viewport, not the data set, is limited to three rows.
static inline NSArray<NSArray<NSString *> *> *NFBEdgeGroups(NSArray<NSString *> *apps,
        NSArray<NSString *> *recent, NSUInteger (^unread)(NSString *)) {
    NSMutableOrderedSet<NSString *> *ordered = [NSMutableOrderedSet orderedSet];
    for (NSString *app in recent) if ([apps containsObject:app]) [ordered addObject:app];
    [ordered addObjectsFromArray:apps];
    NSMutableArray *readApps = [NSMutableArray array];
    NSMutableArray *unreadApps = [NSMutableArray array];
    for (NSString *app in ordered) {
        [(unread(app) ? unreadApps : readApps) addObject:app];
    }
    return @[readApps, unreadApps];
}

// Do not insert an app missing from a user-selected list.
static inline NSArray<NSString *> *NFBPromoteBeyondFour(NSArray<NSString *> *apps, NSString *active, BOOL *promoted) {
    if (promoted) *promoted = NO;
    NSUInteger index = active.length ? [apps indexOfObject:active] : NSNotFound;
    if (index == NSNotFound || index < 4) return apps;
    NSMutableArray *result = [apps mutableCopy];
    [result removeObjectAtIndex:index]; [result insertObject:active atIndex:0];
    if (promoted) *promoted = YES;
    return result;
}
