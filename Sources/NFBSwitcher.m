#import "NFBSwitcher.h"
#import "NFBPrivate.h"
NSArray<NSString *> *NFBReadSwitcherApps(void) {
    id layouts = nil;
    for (NSString *name in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
        layouts = NFBGet(NFBSingleton(name), @"recentAppLayouts");
        if ([layouts isKindOfClass:NSArray.class] || [layouts isKindOfClass:NSOrderedSet.class]) break;
        layouts = nil;
    }
    if (!layouts) return nil;
    NSMutableOrderedSet *apps = [NSMutableOrderedSet orderedSet];
    for (id layout in layouts) {
        id items = NFBGet(layout, @"allItems");
        if (![items isKindOfClass:NSArray.class] && ![items isKindOfClass:NSSet.class] && ![items isKindOfClass:NSOrderedSet.class]) {
            id map = NFBGet(layout, @"rolesToLayoutItemsMap");
            items = [map isKindOfClass:NSDictionary.class] ? [map allValues] : nil;
        }
        BOOL recognized = NO;
        for (id item in items) {
            NSString *app = NFBString(NFBGet(item, @"bundleIdentifier"));
            if (app.length) { [apps addObject:app]; recognized = YES; }
        }
        if (!recognized) {
            id primary = NFBGet(NFBGet(layout, @"protobufRepresentation"), @"primaryDisplayItem");
            NSString *app = NFBString(NFBGet(primary, @"bundleIdentifier"));
            if (app.length) { [apps addObject:app]; recognized = YES; }
        }
        if (!recognized) return nil;
    }
    [apps removeObject:@"com.apple.springboard"];
    return apps.array;
}
