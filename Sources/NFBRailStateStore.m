#import "NFBRailStateStore.h"
#include "NFBRailMetricQueue.h"

// Keys inside the state domain. Versioned so a future format change can be
// detected instead of misread.
static NSString * const NFBRailStateVersionKey = @"RailGeometryVersion";
static NSString * const NFBRailStateTopKey = @"RailSlotTop";
static NSString * const NFBRailStateDiameterKey = @"RailDiameter";
static NSString * const NFBRailStateWidthKey = @"RailScreenWidth";
static const NSInteger NFBRailStateVersion = 1;

@interface NFBRailStateStore ()
// Main-thread confined: the newest geometry still waiting for the debounce, plus
// what is on disk, so repeated identical layouts (the split refresh runs
// continuously) never touch the disk. NFBRailMetricQueue.h owns the rules.
@property(nonatomic) NFBRailMetricQueue queue;
@end

@implementation NFBRailStateStore
+ (NSString *)domain {
    // Separate from CFSTR("local.notifybubbles"): geometry cache, not settings.
    return @"local.notifybubbles.railstate";
}

- (NSNumber *)numberForKey:(NSString *)key {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
            (__bridge CFStringRef)[NFBRailStateStore domain]));
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

- (NFBRailMetric)loadMetric {
    NSAssert(NSThread.isMainThread, @"rail state is read on the main thread");
    CFPreferencesAppSynchronize((__bridge CFStringRef)[NFBRailStateStore domain]);
    NSNumber *version = [self numberForKey:NFBRailStateVersionKey];
    NSNumber *top = [self numberForKey:NFBRailStateTopKey];
    NSNumber *diameter = [self numberForKey:NFBRailStateDiameterKey];
    NSNumber *width = [self numberForKey:NFBRailStateWidthKey];
    NFBRailMetric metric = NFBRailMetricNoRecord();
    if (version && top && diameter && width && version.integerValue == NFBRailStateVersion) {
        metric.top = top.doubleValue;
        metric.diameter = diameter.doubleValue;
        metric.screenWidth = width.doubleValue;
    }
    BOOL valid = NFBRailMetricUsable(metric, metric.screenWidth);
    self.queue = NFBRailMetricQueueLoaded(metric, valid);
    return metric;
}

- (void)saveMetric:(NFBRailMetric)metric {
    if (!NFBRailMetricUsable(metric, metric.screenWidth)) return;
    if (self.queue.committedValid && NFBRailMetricEqual(self.queue.committed, metric)) return;
    NSString *domain = [NFBRailStateStore domain];
    CFPreferencesSetAppValue((__bridge CFStringRef)NFBRailStateVersionKey,
            (__bridge CFPropertyListRef)@(NFBRailStateVersion), (__bridge CFStringRef)domain);
    CFPreferencesSetAppValue((__bridge CFStringRef)NFBRailStateTopKey,
            (__bridge CFPropertyListRef)@(metric.top), (__bridge CFStringRef)domain);
    CFPreferencesSetAppValue((__bridge CFStringRef)NFBRailStateDiameterKey,
            (__bridge CFPropertyListRef)@(metric.diameter), (__bridge CFStringRef)domain);
    CFPreferencesSetAppValue((__bridge CFStringRef)NFBRailStateWidthKey,
            (__bridge CFPropertyListRef)@(metric.screenWidth), (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    NFBRailMetricQueueCommitted(&_queue, metric);
}

- (void)scheduleMetric:(NFBRailMetric)metric after:(NSTimeInterval)delay {
    // Only the newest geometry matters: while a split is open the layout runs at
    // display rate, so A, B and C inside one debounce window must end with C on
    // disk. The queue keeps the latest value; the debounce clock is started once
    // and writes whatever is newest when it fires (NFBRailMetricQueue.h).
    if (!NFBRailMetricQueueOffer(&_queue, metric)) return;
    NSTimeInterval wait = delay > 0 ? delay : 0;
    __weak NFBRailStateStore *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
        NFBRailStateStore *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf flushScheduledMetric];
    });
}
// The debounce fired: commit the newest pending geometry. The clock is consumed
// before the write, so a change offered from inside the write starts its own
// clock instead of being mistaken for the one that just ran (which would keep it
// pending without a timer behind it).
- (void)flushScheduledMetric {
    NFBRailMetric pending = NFBRailMetricNoRecord();
    if (!NFBRailMetricQueueDrain(&self.queue, &pending)) return;
    [self saveMetric:pending];
}
@end
