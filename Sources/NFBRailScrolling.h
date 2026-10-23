#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
// Stop only an obsolete scroll-bounds animation. Never cancel user scrolling
// or unrelated opacity/position animations on the container.
static inline BOOL NFBSettleRailOffset(UIScrollView *rail,CGFloat offset) {
    if (!rail || rail.dragging || rail.decelerating) return NO;
    [rail.layer removeAnimationForKey:@"bounds"];
    [UIView performWithoutAnimation:^{ [rail setContentOffset:CGPointMake(0,offset) animated:NO]; }];
    return YES;
}
