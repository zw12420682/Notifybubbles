#import <Foundation/Foundation.h>
// Partition without losing unread notifications. Apply the four-app budget
// separately to the background container, never to the external unread list.
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

// Membership follows recency, but surviving icons keep their visual order.
// Exclusions are applied before the four-item budget (favorites/unread are elsewhere).
static inline NSArray<NSString *> *NFBRecentFour(NSArray<NSString *> *apps,
        NSArray<NSString *> *recent, NSArray<NSString *> *previous, NSString *active,
        NSArray<NSString *> *excluded) {
    NSMutableOrderedSet<NSString *> *eligible = [NSMutableOrderedSet orderedSetWithArray:apps];
    [eligible removeObjectsInArray:excluded];
    NSMutableOrderedSet<NSString *> *ranked = [NSMutableOrderedSet orderedSet];
    for (NSString *app in recent) if ([eligible containsObject:app]) [ranked addObject:app];
    [ranked addObjectsFromArray:eligible.array];
    NSMutableArray<NSString *> *chosen = [[ranked.array subarrayWithRange:NSMakeRange(0, MIN(4, ranked.count))] mutableCopy];
    if (active.length && [eligible containsObject:active] && ![chosen containsObject:active]) {
        if (chosen.count == 4) [chosen removeLastObject];
        [chosen addObject:active];
    }
    NSMutableOrderedSet<NSString *> *stable = [NSMutableOrderedSet orderedSet];
    for (NSString *app in previous) if ([chosen containsObject:app]) [stable addObject:app];
    [stable addObjectsFromArray:chosen];
    return stable.array;
}
