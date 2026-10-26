#pragma once
#import <Foundation/Foundation.h>
#include "NFBRailState.h"

// Persists the last genuine split column geometry so the first fullscreen layout
// after a SpringBoard relaunch reproduces the same top edge and icon size.
//
// Storage: a dedicated preference domain, not the user's settings domain
// ("local.notifybubbles"). Nothing written here is visible in the settings panel
// and a restore can never change an option. Reads happen once, on the main
// thread, when the manager is created; writes are coalesced (see NFBRailStateStore
// callers) and only fire after a debounce when the geometry really changed.
@interface NFBRailStateStore : NSObject
// Independent state domain; deliberately different from the settings domain.
+ (NSString *)domain;
- (NFBRailMetric)loadMetric;
- (void)saveMetric:(NFBRailMetric)metric;
// Debounced write: the geometry is committed at most once per `delay` seconds
// and only when it differs from what is already on disk / remembered.
- (void)scheduleMetric:(NFBRailMetric)metric after:(NSTimeInterval)delay;
@end
