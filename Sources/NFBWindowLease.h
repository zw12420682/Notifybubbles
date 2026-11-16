#pragma once
#import <UIKit/UIKit.h>
// Main-queue only. A lease controls BOTH level and native hit-test restriction.
// An external level mutation relinquishes both until this host leaves the set.
@interface NFBWindowLease : NSObject
@property(nonatomic, readonly) NSUInteger sessionIdentifier;
- (void)updateHosts:(NSArray<UIWindow *> *)hosts desktop:(UIWindow *)desktop session:(NSUInteger)identifier;
- (BOOL)ownsHost:(UIWindow *)host session:(NSUInteger)identifier;
- (void)releaseSession:(NSUInteger)identifier;
@end
