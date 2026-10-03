#import "NFBPrivacy.h"
#import "NFBDebugLog.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

static __weak UIView *frozenHome;
static BOOL savedInteraction;
static UIVisualEffectView *desktopBlur;

static BOOL NFBVisible(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v = view; v; v = v.superview)
        if (v.hidden || v.alpha < 0.01) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window], view.window.bounds);
}
static UIView *NFBHomeInController(UIViewController *vc) {
    if (!vc.isViewLoaded) return nil;
    Class homeClass = NSClassFromString(@"SBHomeScreenViewController");
    if (homeClass && [vc isKindOfClass:homeClass] && NFBVisible(vc.view)) return vc.view;
    for (UIViewController *child in vc.childViewControllers) {
        UIView *home = NFBHomeInController(child);
        if (home) return home;
    }
    return nil;
}
static BOOL NFBContainsFloatingView(UIView *view) {
    Class floating = NSClassFromString(@"FloatingAppWindow");
    if (floating && [view isKindOfClass:floating]) return YES;
    for (UIView *child in view.subviews)
        if (NFBContainsFloatingView(child)) return YES;
    return NO;
}
void NFBUpdateDesktopFreeze(BOOL enabled, CGFloat opacity) {
    if (!NSThread.isMainThread) return;
    UIView *home = nil;
    if (enabled) {
        if (NFBVisible(frozenHome)) home = frozenHome;
        else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            for (UIWindow *window in UIApplication.sharedApplication.windows) {
                home = NFBHomeInController(window.rootViewController);
                if (home) break;
            }
#pragma clang diagnostic pop
        }
        // Never disable an ancestor of TrollOpen's interactive window.
        if (home && NFBContainsFloatingView(home)) home = nil;
    }
    if (home != frozenHome || !enabled) {
        if (frozenHome) frozenHome.userInteractionEnabled = savedInteraction;
        frozenHome = nil;
        [desktopBlur removeFromSuperview]; desktopBlur = nil;
    }
    if (!home) return;
    if (!frozenHome) {
        frozenHome = home;
        savedInteraction = home.userInteractionEnabled;
        desktopBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
        desktopBlur.frame = home.bounds;
        desktopBlur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        desktopBlur.userInteractionEnabled = NO;
        [home addSubview:desktopBlur];
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 animations:^{
            desktopBlur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        }];
    }
    CGFloat targetAlpha = isfinite(opacity) ? MIN(1, MAX(0, opacity)) : 0.65;
    if (fabs(desktopBlur.alpha - targetAlpha) > 0.001) {
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.15
            delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
            animations:^{ desktopBlur.alpha = targetAlpha; } completion:nil];
    }
    // A fully transparent blur still freezes desktop interaction.
    home.userInteractionEnabled = NO;
    [home bringSubviewToFront:desktopBlur];
}
void NFBSetCaptureHidden(UIView *view, BOOL hidden) {
    if (!view) return;
    CALayer *layer = view.layer;
    static char savedMaskKey;
    NSString *key = @"disableUpdateMask";
    if (![layer respondsToSelector:NSSelectorFromString(key)] ||
        ![layer respondsToSelector:NSSelectorFromString(@"setDisableUpdateMask:")]) return;
    @try {
        NSNumber *saved = objc_getAssociatedObject(layer, &savedMaskKey);
        if (hidden) {
            if (!saved) {
                saved = [layer valueForKey:key];
                objc_setAssociatedObject(layer, &savedMaskKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [layer setValue:@(saved.unsignedIntValue | 0x12) forKey:key];
        } else if (saved) {
            [layer setValue:saved forKey:key];
            objc_setAssociatedObject(layer, &savedMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *exception) { NFBDebugLog(@"capture hiding unavailable: %@", exception); }
}
