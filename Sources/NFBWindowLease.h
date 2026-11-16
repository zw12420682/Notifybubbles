#pragma once
#import <UIKit/UIKit.h>
// Main-queue only. A lease controls BOTH level and native hit-test restriction.
// An external level mutation relinquishes both until this host leaves the set.
@interface NFBWindowLease : NSObject
@property(nonatomic, readonly) NSUInteger sessionIdentifier;
- (void)updateHosts:(NSArray<UIWindow *> *)hosts desktop:(UIWindow *)desktop session:(NSUInteger)identifier;
// Candidate views come from the same Open observation used for movie layout.
// Publication is ignored if its desktop session has already been replaced.
- (void)publishTouchWindows:(NSArray<UIView *> *)windows session:(NSUInteger)identifier;
- (UIView *)nativeHitInHost:(UIWindow *)host point:(CGPoint)point event:(UIEvent *)event session:(NSUInteger)identifier;
- (BOOL)ownsHost:(UIWindow *)host session:(NSUInteger)identifier;
- (void)releaseSession:(NSUInteger)identifier;
@end
