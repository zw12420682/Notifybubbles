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

#import "NFBExitInvocation.h"
static NSArray<NSString *> *NFBLayoutBundleIDs(id layout) {
    id items = NFBGet(layout, @"allItems");
    if (![items isKindOfClass:NSArray.class] && ![items isKindOfClass:NSSet.class] &&
        ![items isKindOfClass:NSOrderedSet.class]) {
        id map = NFBGet(layout, @"rolesToLayoutItemsMap");
        items = [map isKindOfClass:NSDictionary.class] ? [map allValues] : nil;
    }
    NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSet];
    for (id item in items) {
        NSString *app = NFBString(NFBGet(item, @"bundleIdentifier")) ?: NFBString(NFBGet(item, @"displayIdentifier"));
        if (!app.length) return nil; // unknown companion: do not quit its layout
        [ids addObject:app];
    }
    if (!ids.count) {
        id primary = NFBGet(NFBGet(layout, @"protobufRepresentation"), @"primaryDisplayItem");
        NSString *app = NFBString(NFBGet(primary, @"bundleIdentifier"));
        if (!app.length) return nil;
        [ids addObject:app];
    }
    return ids.array;
}
BOOL NFBQuitSwitcherCard(NSString *bundleID, NSString *front, NSString *floating) {
    if (!NSThread.isMainThread || !bundleID.length || [bundleID isEqual:front] ||
        [bundleID isEqual:floating] || [bundleID isEqual:@"com.apple.springboard"]) return NO;
    for (NSString *name in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
        id controller = NFBSingleton(name);
        if (!controller) continue;
        id layouts = NFBGet(controller, @"recentAppLayouts") ?: NFBGet(controller, @"appLayouts");
        if (![layouts isKindOfClass:NSArray.class] && ![layouts isKindOfClass:NSOrderedSet.class]) continue;
        NSArray *snapshot = [layouts isKindOfClass:NSArray.class] ? [layouts copy] : [layouts array];
        for (id layout in snapshot) {
            NSArray *ids = NFBLayoutBundleIDs(layout);
            if (![ids containsObject:bundleID]) continue;
            if ([ids containsObject:front ?: @""] || [ids containsObject:floating ?: @""]) {
                NFBDebugLog(@"switcher: protected shared layout for %@", bundleID);
                return NO;
            }
            if (NFBInvokeQuitLayout(controller, layout)) {
                NFBDebugLog(@"switcher: native card-quit requested %@ on %@", bundleID, name);
                return YES;
            }
            NFBDumpMethods(controller, NO, @"switcher-exit-runtime", @[@"quit", @"deleteapp", @"removecard", @"terminate"]);
        }
    }
    NFBErrorLog(@"switcher: no verified native card-quit entry for %@", bundleID);
    return NO;
}
