#import "NFBStore.h"
@implementation NFBRecord
@end

@interface NFBStore ()
@property(nonatomic, strong) NSMutableArray<NFBRecord *> *records;
@property(nonatomic, strong) NSMutableOrderedSet<NSString *> *pinnedApps;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NFBRecord *> *lastActions;
@end
@implementation NFBStore
- (instancetype)init {
    if ((self = [super init])) {
        _records = [NSMutableArray array];
        _pinnedApps = [NSMutableOrderedSet orderedSet];
        _lastActions = [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSUInteger)count { return self.records.count; }
- (NSArray<NSString *> *)appIDs {
    return self.pinnedApps.array;
}
- (void)putApp:(NSString *)appID notification:(NSString *)notificationID
       request:(id)request destination:(id)destination {
    if (!appID.length || !notificationID.length || !request || !destination) return;
    [self.pinnedApps addObject:appID];
    [self removeApp:appID notification:notificationID];
    NFBRecord *record = [NFBRecord new];
    record.appID = appID; record.notificationID = notificationID;
    record.request = request; record.destination = destination;
    [self.records addObject:record];
    self.lastActions[appID] = record;
    // Bound retained private notification objects during long sessions.
    if (self.records.count > 512) [self.records removeObjectAtIndex:0];
}
- (NFBRecord *)latestForApp:(NSString *)appID {
    for (NFBRecord *record in self.records.reverseObjectEnumerator)
        if ([record.appID isEqualToString:appID]) return record;
    return nil;
}
- (NFBRecord *)actionForApp:(NSString *)appID {
    return [self latestForApp:appID] ?: self.lastActions[appID];
}
- (void)removeApp:(NSString *)appID notification:(NSString *)notificationID {
    NSIndexSet *indexes = [self.records indexesOfObjectsPassingTest:
        ^BOOL(NFBRecord *r, NSUInteger index, BOOL *stop) {
            (void)index; (void)stop;
            return [r.appID isEqualToString:appID] && [r.notificationID isEqualToString:notificationID];
        }];
    [self.records removeObjectsAtIndexes:indexes];
}
- (void)removeApp:(NSString *)appID {
    NSIndexSet *indexes = [self.records indexesOfObjectsPassingTest:
        ^BOOL(NFBRecord *r, NSUInteger index, BOOL *stop) {
            (void)index; (void)stop; return [r.appID isEqualToString:appID];
        }];
    [self.records removeObjectsAtIndexes:indexes];
}
- (void)closeApp:(NSString *)appID {
    [self removeApp:appID];
    [self.pinnedApps removeObject:appID];
    [self.lastActions removeObjectForKey:appID];
}
- (void)clear {
    [self.records removeAllObjects]; [self.pinnedApps removeAllObjects];
    [self.lastActions removeAllObjects];
}
@end
