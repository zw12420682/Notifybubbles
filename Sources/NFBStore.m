#import "NFBStore.h"
@implementation NFBRecord
@end

@interface NFBStore ()
@property(nonatomic, strong) NSMutableArray<NFBRecord *> *records;
@end
@implementation NFBStore
- (instancetype)init {
    if ((self = [super init])) _records = [NSMutableArray array];
    return self;
}
- (NSUInteger)count { return self.records.count; }
- (NSArray<NSString *> *)appIDs {
    NSMutableOrderedSet *apps = [NSMutableOrderedSet orderedSet];
    for (NFBRecord *record in self.records.reverseObjectEnumerator)
        [apps addObject:record.appID];
    return apps.array;
}
- (void)putApp:(NSString *)appID notification:(NSString *)notificationID
       request:(id)request destination:(id)destination {
    if (!appID.length || !notificationID.length || !request || !destination) return;
    [self removeApp:appID notification:notificationID];
    NFBRecord *record = [NFBRecord new];
    record.appID = appID; record.notificationID = notificationID;
    record.request = request; record.destination = destination;
    [self.records addObject:record];
    // Bound retained private notification objects during long sessions.
    if (self.records.count > 512) [self.records removeObjectAtIndex:0];
}
- (NFBRecord *)latestForApp:(NSString *)appID {
    for (NFBRecord *record in self.records.reverseObjectEnumerator)
        if ([record.appID isEqualToString:appID]) return record;
    return nil;
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
- (void)clear { [self.records removeAllObjects]; }
@end
