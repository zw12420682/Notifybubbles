#pragma once
#import <Foundation/Foundation.h>

// User-initiated batch cleanup includes all switcher cards, not just icons in
// the plugin. Never include either currently visible application.
static inline NSArray<NSString *> *NFBBackgroundCleanupTargets(NSArray<NSString *> *switcher,
        NSArray<NSString *> *plugin, NSString *front, NSString *floating) {
    NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSet];
    for (NSArray *source in @[switcher ?: @[], plugin ?: @[]]) {
        for (id candidate in source) {
            if (![candidate isKindOfClass:NSString.class]) continue;
            NSString *app = candidate;
            if (!app.length || [app isEqual:front] || [app isEqual:floating] ||
                [app isEqual:@"com.apple.springboard"] || [app hasPrefix:@"__notifybubbles."]) continue;
            [result addObject:app];
        }
    }
    return result.array;
}
