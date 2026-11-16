#import "NFBWindowLease.h"
#include <math.h>
@interface NFBWindowLeaseEntry : NSObject
@property(nonatomic) CGFloat original, applied;
@property(nonatomic) BOOL relinquished;
@end
@implementation NFBWindowLeaseEntry @end
@interface NFBWindowLease ()
@property(nonatomic,readwrite) NSUInteger sessionIdentifier;
@property(nonatomic,strong) NSMapTable<UIWindow *,NFBWindowLeaseEntry *> *entries;
@property(nonatomic,weak) UIWindow *desktop;
@end
@implementation NFBWindowLease
- (instancetype)init {
    if ((self=[super init])) _entries=[NSMapTable weakToStrongObjectsMapTable];
    return self;
}
- (void)releaseHost:(UIWindow *)host {
    NFBWindowLeaseEntry *entry=[self.entries objectForKey:host];
    if (!entry.relinquished && fabs(host.windowLevel-entry.applied)<0.01)
        host.windowLevel=entry.original;
    [self.entries removeObjectForKey:host];
}
- (void)releaseSession:(NSUInteger)identifier {
    NSAssert(NSThread.isMainThread,@"window leases require main queue");
    if (identifier!=self.sessionIdentifier) return; // old teardown cannot release new session
    for (UIWindow *host in self.entries.keyEnumerator.allObjects) [self releaseHost:host];
    self.desktop=nil; self.sessionIdentifier=0;
}
- (void)updateHosts:(NSArray<UIWindow *> *)hosts desktop:(UIWindow *)desktop session:(NSUInteger)identifier {
    NSAssert(NSThread.isMainThread,@"window leases require main queue");
    if (identifier!=self.sessionIdentifier || desktop!=self.desktop) {
        [self releaseSession:self.sessionIdentifier];
        self.sessionIdentifier=identifier; self.desktop=desktop;
    }
    for (UIWindow *old in self.entries.keyEnumerator.allObjects)
        if (![hosts containsObject:old]) [self releaseHost:old];
    if (!identifier || !desktop) return;
    for (UIWindow *host in hosts) {
        if (host==desktop) continue;
        NFBWindowLeaseEntry *entry=[self.entries objectForKey:host];
        if (entry && !entry.relinquished && fabs(host.windowLevel-entry.applied)>=0.01)
            entry.relinquished=YES;
        if (entry.relinquished) continue;
        if (host.hidden || host.alpha<0.01 || !host.userInteractionEnabled) {
            if (entry) [self releaseHost:host];
            continue;
        }
        if (!entry) {
            entry=[NFBWindowLeaseEntry new]; entry.original=host.windowLevel;
            [self.entries setObject:entry forKey:host];
        }
        entry.applied=desktop.windowLevel+1;
        if (fabs(host.windowLevel-entry.applied)>=0.01) host.windowLevel=entry.applied;
    }
}
- (BOOL)ownsHost:(UIWindow *)host session:(NSUInteger)identifier {
    NFBWindowLeaseEntry *entry=[self.entries objectForKey:host];
    if (!entry || !identifier || identifier!=self.sessionIdentifier || entry.relinquished) return NO;
    // Check at hit-test time too: do not wait for the next layout observation.
    if (fabs(host.windowLevel-entry.applied)>=0.01) { entry.relinquished=YES; return NO; }
    return self.desktop && host!=self.desktop && !host.hidden && host.alpha>=0.01 && host.userInteractionEnabled;
}
@end
