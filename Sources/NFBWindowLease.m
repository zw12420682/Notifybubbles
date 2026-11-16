#import "NFBWindowLease.h"
#include <math.h>
@interface NFBWindowLeaseEntry : NSObject
@property(nonatomic) CGFloat original, applied;
@property(nonatomic) BOOL relinquished;
@property(nonatomic,strong) NSHashTable<UIView *> *touchWindows;
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
- (void)publishTouchWindows:(NSArray<UIView *> *)windows session:(NSUInteger)identifier {
    NSAssert(NSThread.isMainThread,@"touch candidates require main queue");
    if (!identifier || identifier!=self.sessionIdentifier) return;
    for (UIWindow *host in self.entries.keyEnumerator.allObjects) {
        NFBWindowLeaseEntry *entry=[self.entries objectForKey:host];
        entry.touchWindows=[NSHashTable weakObjectsHashTable];
        if (entry.relinquished) continue;
        for (UIView *view in windows)
            if (view!=host && view.window==host) [entry.touchWindows addObject:view];
    }
}
- (UIView *)nativeHitInHost:(UIWindow *)host point:(CGPoint)point event:(UIEvent *)event session:(NSUInteger)identifier {
    NSAssert(NSThread.isMainThread,@"touch routing requires main queue");
    if (![self ownsHost:host session:identifier]) return nil;
    NFBWindowLeaseEntry *entry=[self.entries objectForKey:host];
    // Follow the current native hierarchy/z order, but only within the captured
    // candidate set. Frames are converted at touch time so animations remain live.
    NSMutableArray<UIView *> *ordered=[NSMutableArray array];
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:host];
    while (pending.count) {
        UIView *view=pending.lastObject; [pending removeLastObject];
        if (view.hidden || view.alpha<0.01 || !view.userInteractionEnabled) continue;
        CGPoint local=[view convertPoint:point fromView:host];
        if (view.clipsToBounds && ![view pointInside:local withEvent:event]) continue;
        if ([entry.touchWindows containsObject:view]) { [ordered addObject:view]; continue; }
        // Never inspect arbitrary app content. Only traverse ancestors of the
        // observed floating roots; unrelated sibling trees are skipped.
        BOOL ancestor=(view==host);
        if (!ancestor) for (UIView *root in entry.touchWindows)
            if ([root isDescendantOfView:view] && root.window==host) { ancestor=YES; break; }
        if (!ancestor) continue;
        NSArray *children=[view.subviews sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            if (a.layer.zPosition<b.layer.zPosition) return NSOrderedAscending;
            if (a.layer.zPosition>b.layer.zPosition) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        [pending addObjectsFromArray:children]; // last/frontmost is popped first
    }
    for (UIView *view in ordered) {
        if (view.window!=host || ![view isDescendantOfView:host]) continue;
        CGPoint local=[view convertPoint:point fromView:host];
        if (![view pointInside:local withEvent:event]) continue;
        UIView *hit=[view hitTest:local withEvent:event];
        if (hit.window==host && (hit==view || [hit isDescendantOfView:view])) return hit;
    }
    return nil;
}
- (BOOL)ownsHost:(UIWindow *)host session:(NSUInteger)identifier {
    NFBWindowLeaseEntry *entry=[self.entries objectForKey:host];
    if (!entry || !identifier || identifier!=self.sessionIdentifier || entry.relinquished) return NO;
    // Check at hit-test time too: do not wait for the next layout observation.
    if (fabs(host.windowLevel-entry.applied)>=0.01) { entry.relinquished=YES; return NO; }
    return self.desktop && host!=self.desktop && !host.hidden && host.alpha>=0.01 && host.userInteractionEnabled;
}
@end
