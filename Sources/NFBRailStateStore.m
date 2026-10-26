#import "NFBRailStateStore.h"

// Keys inside the state domain. Versioned so a future format change can be
// detected instead of misread.
static NSString * const NFBRailStateVersionKey = @"RailGeometryVersion";
static NSString * const NFBRailStateTopKey = @"RailSlotTop";
static NSString * const NFBRailStateDiameterKey = @"RailDiameter";
static NSString * const NFBRailStateWidthKey = @"RailScreenWidth";
static const NSInteger NFBRailStateVersion = 1;

@interface NFBRailStateStore ()
// Main-thread confined: what was last read or queued, so repeated identical
// layouts (the split refresh runs continuously) never touch the disk.
@property(nonatomic) NFBRailMetric committed;
@property(nonatomic) BOOL committedValid;
@property(nonatomic) NSUInteger writeToken;
@property(nonatomic) BOOL queued;
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
    self.committedValid = NFBRailMetricUsable(metric, metric.screenWidth);
    if (self.committedValid) self.committed = metric;
    return metric;
}

- (void)saveMetric:(NFBRailMetric)metric {
    if (!NFBRailMetricUsable(metric, metric.screenWidth)) return;
    if (self.committedValid && NFBRailMetricEqual(self.committed, metric)) return;
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
    self.committed = metric;
    self.committedValid = YES;
    self.queued = NO;
}

- (void)scheduleMetric:(NFBRailMetric)metric after:(NSTimeInterval)delay {
    if (!NFBRailMetricUsable(metric, metric.screenWidth)) return;
    if (self.committedValid && NFBRailMetricEqual(self.committed, metric)) return;
    // Only the newest geometry matters: while a split is open the layout runs at
    // display rate, and each call would otherwise queue its own write.
    ++self.writeToken;
    if (self.queued) return;
    self.queued = YES;
    NSTimeInterval wait = delay > 0 ? delay : 0;
    __weak NFBRailStateStore *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
        NFBRailStateStore *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.queued = NO;
        [strongSelf saveMetric:metric];
    });
}
@end
