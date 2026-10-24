#import "NFBStore.h"
#import <objc/message.h>
#import "NFBInterfaces.h"
static NSDate *NFBRequestDate(id request) {
    SEL sel = NSSelectorFromString(@"timestamp");
    NSMethodSignature *sig = NFBSignature(request, sel);
    if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(request, sel);
        return [value isKindOfClass:NSDate.class] ? value : nil;
    } @catch (__unused NSException *error) { return nil; }
}
NSString *NFBRevisionForRequest(id request) {
    NSDate *date = NFBRequestDate(request);
    return date ? [NSString stringWithFormat:@"%.6f", date.timeIntervalSince1970] : nil;
}
@implementation NFBRecord
@end
@interface NFBStore ()
@property(nonatomic, strong) NSMutableArray<NFBRecord *> *records;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NFBRecord *> *> *recordsByApp;
- (void)eraseRecord:(NFBRecord *)record;
@property(nonatomic, strong) NSMutableOrderedSet<NSString *> *pins;
@property(nonatomic, strong) NSMutableOrderedSet<NSArray<NSString *> *> *consumed;
@end
@implementation NFBStore
- (instancetype)init {
    if ((self = [super init])) {
        _records = [NSMutableArray array]; _pins = [NSMutableOrderedSet orderedSet];
        _consumed = [NSMutableOrderedSet orderedSet];
        _recordsByApp = [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSUInteger)count { return self.records.count; }
- (NSArray<NSString *> *)appIDs { return self.pins.array; }
- (void)pinApp:(NSString *)appID {
    // Switcher cards append ABOVE the existing bubbles: the first bubble stays
    // anchored at the bottom (index 0 = lowest) and never moves, while each new
    // bubble stacks upward on top of it.
    if (appID.length) [self.pins addObject:appID];
}
- (void)promoteApp:(NSString *)appID {
    if (![self.pins containsObject:appID]) return;
    [self.pins removeObject:appID]; [self.pins insertObject:appID atIndex:0];
}
- (BOOL)putApp:(NSString *)appID notification:(NSString *)notificationID request:(id)request destination:(id)destination {
    if (!appID.length || !notificationID.length || !request || !destination) return NO;
    NSDate *date = NFBRequestDate(request);
    NSString *revision = date ? [NSString stringWithFormat:@"%.6f", date.timeIntervalSince1970] : @"undated";
    if ([self.consumed containsObject:@[appID, notificationID, revision]]) return NO;
    for (NFBRecord *existing in [self.recordsByApp[appID] copy]) {
        if ([existing.appID isEqual:appID] && [existing.notificationID isEqual:notificationID]) {
            if ([existing.revision isEqual:revision]) {
                existing.request = request; existing.destination = destination; return NO;
            }
            [self eraseRecord:existing];
        }
    }
    NFBRecord *record = [NFBRecord new];
    record.appID = appID; record.notificationID = notificationID;
    record.request = request; record.destination = destination;
    record.timestamp = date ?: [NSDate date]; record.revision = revision;
    [self.records addObject:record];
    if (!self.recordsByApp[appID]) self.recordsByApp[appID] = [NSMutableArray array];
    [self.recordsByApp[appID] addObject:record];
    // A brand-new app joins ABOVE the existing bubbles (append): the first
    // bubble keeps its spot at the bottom (index 0 = lowest, per NFBRowCenter's
    // "first icon is lowest" geometry) and never moves, while each new bubble
    // stacks upward on top of it. An app that already has a bubble keeps its
    // position (no re-promotion).
    if (![self.pins containsObject:appID]) [self.pins addObject:appID];
    if (self.records.count > 512) [self eraseRecord:self.records.firstObject];
    return YES;
}
- (NFBRecord *)latestForApp:(NSString *)appID {
    NFBRecord *latest = nil;
    for (NFBRecord *r in self.recordsByApp[appID])
        if ([r.appID isEqual:appID] && (!latest || [r.timestamp compare:latest.timestamp] != NSOrderedAscending)) latest = r;
    return latest;
}
- (NSUInteger)countForApp:(NSString *)appID {
    return self.recordsByApp[appID].count;
}
- (void)eraseRecord:(NFBRecord *)record {
    [self.records removeObjectIdenticalTo:record];
    NSMutableArray *appRecords = self.recordsByApp[record.appID];
    [appRecords removeObjectIdenticalTo:record];
    if (!appRecords.count) [self.recordsByApp removeObjectForKey:record.appID];
}
- (void)consumeRecord:(NFBRecord *)record {
    if (!record) return;
    [self.consumed addObject:@[record.appID, record.notificationID, record.revision]];
    if (self.consumed.count > 1024) [self.consumed removeObjectAtIndex:0];
    [self eraseRecord:record];
}
- (void)removeApp:(NSString *)appID notification:(NSString *)notificationID {
    [self removeApp:appID notification:notificationID revision:nil];
}
- (void)removeApp:(NSString *)appID notification:(NSString *)notificationID revision:(NSString *)revision {
    for (NFBRecord *r in [self.recordsByApp[appID] copy])
        if ([r.notificationID isEqual:notificationID] && (!revision || [r.revision isEqual:revision])) [self eraseRecord:r];
}
- (void)removeApp:(NSString *)appID {
    for (NFBRecord *r in [self.recordsByApp[appID] copy]) [self consumeRecord:r];
}
- (void)closeApp:(NSString *)appID { [self removeApp:appID]; [self.pins removeObject:appID]; }
- (void)clear { for (NSString *app in self.appIDs) [self closeApp:app]; }
@end
