#import "NFBStore.h"
#import <objc/message.h>
static NSDate *NFBRequestDate(id request) {
    SEL sel = NSSelectorFromString(@"timestamp");
    NSMethodSignature *sig = [request methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(request, sel);
    return [value isKindOfClass:NSDate.class] ? value : nil;
}
@implementation NFBRecord
@end
@interface NFBStore ()
@property(nonatomic, strong) NSMutableArray<NFBRecord *> *records;
@property(nonatomic, strong) NSMutableOrderedSet<NSString *> *pins;
@property(nonatomic, strong) NSMutableOrderedSet<NSArray<NSString *> *> *consumed;
@end
@implementation NFBStore
- (instancetype)init {
    if ((self = [super init])) {
        _records = [NSMutableArray array]; _pins = [NSMutableOrderedSet orderedSet];
        _consumed = [NSMutableOrderedSet orderedSet];
    }
    return self;
}
- (NSUInteger)count { return self.records.count; }
- (NSArray<NSString *> *)appIDs { return self.pins.array; }
- (void)pinApp:(NSString *)appID { if (appID.length) [self.pins addObject:appID]; }
- (void)promoteApp:(NSString *)appID {
    if (![self.pins containsObject:appID]) return;
    [self.pins removeObject:appID]; [self.pins insertObject:appID atIndex:0];
}
- (BOOL)putApp:(NSString *)appID notification:(NSString *)notificationID request:(id)request destination:(id)destination {
    if (!appID.length || !notificationID.length || !request || !destination) return NO;
    NSDate *date = NFBRequestDate(request);
    NSString *revision = date ? [NSString stringWithFormat:@"%.6f", date.timeIntervalSince1970] : @"undated";
    if ([self.consumed containsObject:@[appID, notificationID, revision]]) return NO;
    for (NFBRecord *existing in [self.records copy]) {
        if ([existing.appID isEqual:appID] && [existing.notificationID isEqual:notificationID]) {
            if ([existing.revision isEqual:revision]) {
                existing.request = request; existing.destination = destination; return NO;
            }
            [self.records removeObject:existing];
        }
    }
    NFBRecord *record = [NFBRecord new];
    record.appID = appID; record.notificationID = notificationID;
    record.request = request; record.destination = destination;
    record.timestamp = date ?: [NSDate date]; record.revision = revision;
    [self.records addObject:record];
    // A brand-new app joins the BOTTOM of the row: with NFBRowCenter's
    // "first icon is lowest" geometry, index 0 is the lowest bubble, so the row
    // grows from the bottom upward and every new bubble pushes the rest up.
    // An app that already has a bubble keeps its position (no re-promotion).
    if (![self.pins containsObject:appID]) [self.pins insertObject:appID atIndex:0];
    if (self.records.count > 512) [self.records removeObjectAtIndex:0];
    return YES;
}
- (NFBRecord *)latestForApp:(NSString *)appID {
    NFBRecord *latest = nil;
    for (NFBRecord *r in self.records)
        if ([r.appID isEqual:appID] && (!latest || [r.timestamp compare:latest.timestamp] != NSOrderedAscending)) latest = r;
    return latest;
}
- (NSUInteger)countForApp:(NSString *)appID {
    NSUInteger n = 0;
    for (NFBRecord *r in self.records)
        if ([r.appID isEqual:appID]) n++;
    return n;
}
- (void)consumeRecord:(NFBRecord *)record {
    if (!record) return;
    [self.consumed addObject:@[record.appID, record.notificationID, record.revision]];
    if (self.consumed.count > 1024) [self.consumed removeObjectAtIndex:0];
    [self.records removeObjectIdenticalTo:record];
}
- (void)removeApp:(NSString *)appID notification:(NSString *)notificationID {
    NSIndexSet *indexes = [self.records indexesOfObjectsPassingTest:^BOOL(NFBRecord *r, NSUInteger i, BOOL *stop) {
        (void)i; (void)stop; return [r.appID isEqual:appID] && [r.notificationID isEqual:notificationID];
    }];
    [self.records removeObjectsAtIndexes:indexes];
}
- (void)removeApp:(NSString *)appID {
    for (NFBRecord *r in [self.records copy]) if ([r.appID isEqual:appID]) [self consumeRecord:r];
}
- (void)closeApp:(NSString *)appID { [self removeApp:appID]; [self.pins removeObject:appID]; }
- (void)clear { for (NSString *app in self.appIDs) [self closeApp:app]; }
@end
