#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#include <math.h>
#import "NFBDebugLog.h"

// Main-thread only. Never change hit testing, key window, gestures or geometry.
static __weak UIWindow *nfbArcWindow;
static CGFloat nfbArcOriginalLevel, nfbArcAppliedLevel;
static BOOL nfbArcOwnsLevel, nfbArcRelinquished;
static BOOL NFBArcOwnedImage(Class cls) {
    Dl_info info={0};
    return dladdr((__bridge const void *)cls,&info) && info.dli_fname &&
        [[[NSString stringWithUTF8String:info.dli_fname] lastPathComponent] isEqualToString:@"TrollOpenJB.dylib"];
}
static BOOL NFBArcVisibleMenu(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth>12 || view.hidden || view.alpha<0.01 ||
        view.layer.hidden || view.layer.opacity<0.01) return NO;
    --*budget;
    if ([NSStringFromClass(view.class) isEqualToString:@"WatchMenuView"] &&
        NFBArcOwnedImage(view.class) && !CGRectIsEmpty(view.bounds)) return YES;
    for (UIView *child in view.subviews)
        if (NFBArcVisibleMenu(child,depth+1,budget)) return YES;
    return NO;
}
static void NFBRestoreArcOverlay(void) {
    UIWindow *window=nfbArcWindow;
    if (window && nfbArcOwnsLevel && fabs(window.windowLevel-nfbArcAppliedLevel)<0.01) {
        window.windowLevel=nfbArcOriginalLevel;
        NFBDebugLog(@"arc-overlay: restored window=%p level=%.2f",window,nfbArcOriginalLevel);
    }
    nfbArcWindow=nil; nfbArcOwnsLevel=NO; nfbArcRelinquished=NO;
}
static void NFBUpdateArcOverlay(BOOL enabled) {
    if (!enabled) { NFBRestoreArcOverlay(); return; }
    NSMutableArray<UIWindow *> *windows=[NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    UIWindow *candidate=nil;
    CGFloat target=2002; // Above our rail (2001), movie desktop (1001), video (1002).
    for (UIWindow *window in windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"NFBWindow"] &&
            !window.hidden && window.alpha>=0.01 && isfinite(window.windowLevel))
            target=MAX(target,window.windowLevel+1);
        if (![NSStringFromClass(window.class) isEqualToString:@"TOJBW0"] ||
            !NFBArcOwnedImage(window.class)) continue;
        NSUInteger budget=128;
        if (NFBArcVisibleMenu(window,0,&budget)) candidate=window;
    }
    if (candidate!=nfbArcWindow) {
        NFBRestoreArcOverlay();
        nfbArcWindow=candidate;
    }
    if (!candidate) return;
    if (nfbArcOwnsLevel && fabs(candidate.windowLevel-nfbArcAppliedLevel)>=0.01) {
        // Another owner changed it: do not fight or later overwrite its value.
        nfbArcOwnsLevel=NO; nfbArcRelinquished=YES;
        NFBDebugLog(@"arc-overlay: external level change; relinquished window=%p",candidate);
    }
    if (nfbArcRelinquished) return;
    if (!nfbArcOwnsLevel) {
        if (!isfinite(candidate.windowLevel) || candidate.windowLevel>=target) return;
        nfbArcOriginalLevel=candidate.windowLevel;
        nfbArcAppliedLevel=target; nfbArcOwnsLevel=YES;
        candidate.windowLevel=target;
        NFBDebugLog(@"arc-overlay: raised window=%p original=%.2f applied=%.2f menu=WatchMenuView",candidate,nfbArcOriginalLevel,target);
    } else if (target>nfbArcAppliedLevel) {
        nfbArcAppliedLevel=target; candidate.windowLevel=target;
    }
}
