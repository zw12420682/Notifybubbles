#import "NFBDesktopHost.h"
#ifndef NFB_DESKTOP_SIM_TEST
#import "NFBWidgetDetachTrace.h"
#endif
#import "NFBWindowLease.h"
#import "NFBSplitCoordinator.h"
#import "NFBDesktopGeometry.h"
#import "NFBInterfaces.h"
#import "NFBWindowState.h"
#import "NFBSystemDesktop.h"
#import "NFBDebugLog.h"
#import "NFBPrivacy.h"
#import "NFBTrollOpen.h"
#import "NFBStateLedger.h"
#import <QuartzCore/QuartzCore.h>
#ifndef NFB_DESKTOP_SIM_TEST
#import <substrate.h>
#endif
#include <math.h>
static NSArray<UIWindow *> *NFBDesktopWindows(void);

typedef NS_ENUM(NSUInteger, NFBDesktopMutationPhase) {
    NFBDesktopMutationPreparing, NFBDesktopMutationTransferred,
    NFBDesktopMutationActive, NFBDesktopMutationRestoring, NFBDesktopMutationFinished
};
@interface NFBDesktopSession : NSObject
@property(nonatomic) NSUInteger identifier;
@property(nonatomic) NFBDesktopMutationPhase mutationPhase;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIView *canvas;
@property(nonatomic, strong) UIView *desktopHost;
@property(nonatomic, strong) UIView *desktop;
@property(nonatomic, strong) UIView *originalParent;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, strong) UIView *independentAnchor;
@property(nonatomic) NSUInteger originalIndex;
@property(nonatomic) CGRect originalBounds;
@property(nonatomic) CGPoint originalCenter;
@property(nonatomic) CGAffineTransform originalTransform;
@property(nonatomic) UIViewAutoresizing originalAutoresizing;
@property(nonatomic) BOOL originalTranslates, originalHidden, originalInteraction;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) UIVisualEffectView *backgroundFrost;
@property(nonatomic) NSUInteger wallpaperCount;
@property(nonatomic,strong) NFBStateLedger *appearanceState, *interactionState, *siblingState;
@property(nonatomic) CFTimeInterval lastInteractionScan;
@property(nonatomic,strong) NSHashTable<UIView *> *knownInteractiveViews;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic) CGFloat originalWindowLevel, originalWindowAlpha, hostedWindowLevel;
@property(nonatomic) BOOL loweredForMoviePark;
@property(nonatomic) BOOL originalWindowHidden, originalWindowInteraction, windowMutated;
@property(nonatomic,strong) UIColor *originalWindowColor;
@property(nonatomic) BOOL originalWindowOpaque;
@property(nonatomic) NSUInteger blockedHitReports;
@property(nonatomic,copy) NSString *pendingApp;
@property(nonatomic) CFTimeInterval pendingDeadline;
@property(nonatomic,strong) UIScrollView *refreshScroll;
@property(nonatomic) CGPoint refreshOffset;
@property(nonatomic,strong) UIView *refreshCover;
@property(nonatomic) NSUInteger widgetRefreshAttempts;
@property(nonatomic) BOOL widgetRefreshFinished;
@property(nonatomic) BOOL widgetRefreshCancelled;
- (void)scheduleWidgetRefreshRetry;
- (void)refreshWidgetPage;
- (void)finishWidgetRefresh;
- (void)activateDesktop;
- (void)adoptDesktopInteraction;
- (void)restoreDesktopInteraction;
@property(nonatomic) BOOL startedHome;
@property(nonatomic) CGRect panelFrame;
@property(nonatomic) BOOL placed;
@property(nonatomic) BOOL restoring, mutated;
@property(nonatomic) BOOL movieParked, moviePersistent;
- (BOOL)place;
- (void)check;
- (void)checkBody;
- (void)restore;
- (void)adoptDesktopAppearance;
- (void)installPaneBackdrop;
- (void)restoreDesktopAppearance;
@end
static NFBDesktopSession *session;
static NSUInteger desktopSequence;
static NFBWindowLease *NFBMovieHostLease(void);
#ifdef NFB_DESKTOP_SIM_TEST
// Simulator-only one-shot fault injection; never compiled into the tweak.
static NSUInteger desktopFailurePoint;
void NFBDesktopTestFailAt(NSUInteger point) { desktopFailurePoint=point; }
static void NFBDesktopTestCheckpoint(NSUInteger point) {
    if (desktopFailurePoint!=point) return;
    desktopFailurePoint=0;
    [NSException raise:@"DesktopTransactionFixture" format:@"checkpoint %lu",(unsigned long)point];
}
#else
#define NFBDesktopTestCheckpoint(point) ((void)0)
#endif

NSUInteger NFBDesktopSessionIdentifier(void) { return session && !session.restoring ? session.identifier : 0; }
BOOL NFBMovieDesktopParked(void) { return session && !session.restoring && session.movieParked; }
void NFBSetMovieDesktopParked(NSUInteger identifier, BOOL parked) {
    if (!NSThread.isMainThread || !session || session.restoring || !identifier || session.identifier!=identifier) return;
    NFBDesktopSession *active=session;
    active.moviePersistent=YES;
    if (active.movieParked==parked) return;
    active.movieParked=parked;
    if (parked) {
        [NFBMovieHostLease() releaseSession:identifier];
        active.widgetRefreshCancelled=YES;
        [active finishWidgetRefresh];
        active.pendingApp=nil;
        // Hide only our panel, not the shared native home window. Keep its
        // desktop subtree attached. The existing hit hook returns nil below.
        [active.panel.layer removeAllAnimations];
        active.panel.hidden=YES; active.panel.userInteractionEnabled=NO;
        active.backgroundFrost.hidden=YES;
        // The home host must not remain above the now-unleased Open windows.
        active.loweredForMoviePark=active.window.windowLevel==active.hostedWindowLevel;
        if (active.loweredForMoviePark) active.window.windowLevel=active.originalWindowLevel;
        if (active.window.isKeyWindow && active.previousKeyWindow && !active.previousKeyWindow.hidden)
            [active.previousKeyWindow makeKeyWindow];
    } else {
        if (active.loweredForMoviePark && active.window.windowLevel==active.originalWindowLevel)
            active.window.windowLevel=active.hostedWindowLevel;
        active.loweredForMoviePark=NO;
        active.backgroundFrost.hidden=NO;
        // No re-transplant, refresh, focus acquisition or opening animation.
        [UIView performWithoutAnimation:^{
            active.panel.transform=CGAffineTransformIdentity; active.panel.alpha=1;
            if (active.desktop.superview==active.desktopHost) {
                NFBDebugLog(@"movie-desktop: resume content hidden=%d alpha=%.2f",active.desktop.hidden,active.desktop.alpha);
                active.desktop.hidden=NO;
                active.desktop.alpha=1;
                [active adoptDesktopAppearance];
            }
            active.panel.hidden=NO; active.panel.userInteractionEnabled=YES;
        }];
    }
    NFBDebugLog(@"movie-desktop: session=%lu parked=%d",(unsigned long)identifier,parked);
    NFBDebugLog(@"movie-desktop: host level=%.1f original=%.1f hosted=%.1f key=%d",
        active.window.windowLevel,active.originalWindowLevel,active.hostedWindowLevel,active.window.isKeyWindow);
}
static UIScrollView *NFBDesktopPager(UIView *desktop);
static void NFBLogWidgetHosts(UIView *view, NSUInteger depth, NSUInteger *budget);
// Object tracking distinguishes deallocation/detachment from tree scan limits.
@interface NFBWidgetWatch : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic,copy) NSString *kind, *address, *parentAddress;
@property(nonatomic) NSUInteger token;
@end
@implementation NFBWidgetWatch @end
static NSMutableArray<NFBWidgetWatch *> *widgetWatches;
static NSUInteger widgetWatchSequence;
static BOOL NFBWidgetWatchCandidate(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    return [name containsString:@"WidgetHost"] || [name containsString:@"WidgetContainer"] ||
        [name containsString:@"ScenePresentation"] || [name containsString:@"SceneLayerHost"];
}
static void NFBTrackWidget(UIView *view) {
    if (!NFBDebugLoggingEnabled() || !NFBWidgetWatchCandidate(view)) return;
    if (!widgetWatches) widgetWatches=[NSMutableArray array];
    for (NFBWidgetWatch *watch in widgetWatches) if (watch.view==view) return;
    // Bounded history includes dead weak references; no view or controller retained.
    if (widgetWatches.count>=96) [widgetWatches removeObjectAtIndex:0];
    NFBWidgetWatch *watch=[NFBWidgetWatch new]; watch.view=view;
    watch.kind=NSStringFromClass(view.class); watch.address=[NSString stringWithFormat:@"%p",view];
    watch.parentAddress=[NSString stringWithFormat:@"%p",view.superview]; watch.token=++widgetWatchSequence;
    [widgetWatches addObject:watch];
    NFBDebugLog(@"widget-watch: discovered id=%lu kind=%@ view=%@ parent=%@",(unsigned long)watch.token,watch.kind,watch.address,watch.parentAddress);
}
static void NFBWidgetWatchSample(const char *phase) {
    if (!NFBDebugLoggingEnabled()) return;
    NSUInteger visited=0, depthHits=0, newBefore=widgetWatchSequence;
    NSMutableArray<UIView *> *pending=[NSMutableArray array];
    NSMutableArray<NSNumber *> *depths=[NSMutableArray array];
    for (UIWindow *window in NFBDesktopWindows())
        if ([NSStringFromClass(window.class) isEqualToString:@"SBHomeScreenWindow"]) {
            [pending addObject:window]; [depths addObject:@0];
        }
    // Traverse hidden branches too, but never call layout or instantiate views.
    while (pending.count && visited<4096) {
        UIView *view=pending.lastObject; [pending removeLastObject];
        NSUInteger depth=depths.lastObject.unsignedIntegerValue; [depths removeLastObject]; visited++;
        NFBTrackWidget(view);
        if (depth>=40) { if (view.subviews.count) depthHits++; continue; }
        for (UIView *child in view.subviews) { [pending addObject:child]; [depths addObject:@(depth+1)]; }
    }
    NFBDebugLog(@"widget-watch: scan phase=%s nodes=%lu pending=%lu depthLimitHits=%lu new=%lu tracked=%lu session=%lu",
        phase,(unsigned long)visited,(unsigned long)pending.count,(unsigned long)depthHits,
        (unsigned long)(widgetWatchSequence-newBefore),(unsigned long)widgetWatches.count,(unsigned long)NFBDesktopSessionIdentifier());
    for (NFBWidgetWatch *watch in widgetWatches) {
        UIView *view=watch.view;
        NFBDebugLog(@"widget-watch: phase=%s id=%lu kind=%@ original=%@ alive=%d parent=%p originalParent=%@ window=%p hidden=%d alpha=%.2f children=%lu",
            phase,(unsigned long)watch.token,watch.kind,watch.address,view!=nil,view.superview,watch.parentAddress,
            view.window,view.hidden,view.alpha,(unsigned long)view.subviews.count);
        if (!view) continue;
        NSUInteger depth=0;
        NSMutableArray<NSString *> *chain=[NSMutableArray array];
        for (UIView *ancestor=view; ancestor && depth<24; ancestor=ancestor.superview,depth++) {
            [chain addObject:[NSString stringWithFormat:@"%@(%p hidden=%d alpha=%.2f layerHidden=%d opacity=%.2f clips=%d mask=%@)",
                NSStringFromClass(ancestor.class),ancestor,ancestor.hidden,ancestor.alpha,ancestor.layer.hidden,
                ancestor.layer.opacity,ancestor.clipsToBounds,NSStringFromClass(ancestor.layer.mask.class)]];
        }
        NFBDebugLog(@"widget-watch: ancestors phase=%s id=%lu count=%lu chain=%@",phase,
            (unsigned long)watch.token,(unsigned long)depth,[chain componentsJoinedByString:@" -> "]);
        // Only inspect an existing responder/controller; never request its view.
        UIResponder *responder=view.nextResponder;
        NSUInteger steps=0;
        while (responder && ![responder isKindOfClass:UIViewController.class] && steps++<16) responder=responder.nextResponder;
        if ([responder isKindOfClass:UIViewController.class]) {
            UIViewController *controller=(UIViewController *)responder;
            NFBDebugLog(@"widget-watch: controller phase=%s id=%lu class=%@ loaded=%d parent=%@ presenting=%@",
                phase,(unsigned long)watch.token,NSStringFromClass(controller.class),controller.isViewLoaded,
                NSStringFromClass(controller.parentViewController.class),NSStringFromClass(controller.presentingViewController.class));
        }
    }
}

// Lock diagnostics are observational only: no refresh, page change, snapshot,
// overlay or gesture. The native desktop and widget trees are read in place.
static void NFBLogLockHomeWidgets(const char *phase) {
    if (!NFBDebugLoggingEnabled()) return;
    NSArray<UIWindow *> *windows=NFBDesktopWindows();
    NFBDebugLog(@"home-lock: %s windows=%lu",phase,(unsigned long)windows.count);
    for (UIWindow *window in windows) {
        if (window.hidden || window.alpha<0.01) continue;
        NFBDebugLog(@"home-lock: %s window=%p class=%@ level=%.1f hidden=%d",
            phase,window,NSStringFromClass(window.class),window.windowLevel,window.hidden);
    }
    for (UIWindow *window in windows) {
        if (![NSStringFromClass(window.class) isEqualToString:@"SBHomeScreenWindow"] || window.hidden) continue;
        UIView *root=window.rootViewController.view;
        NSUInteger budget=48;
        UIScrollView *pager=NFBDesktopPager(root);
        NFBDebugLog(@"home-lock: %s root=%@ pager=%@ offset=%@ size=%@ content=%@ idle=%d session=%d",
            phase,NSStringFromClass(root.class),pager?NSStringFromClass(pager.class):@"none",
            pager?NSStringFromCGPoint(pager.contentOffset):@"none",
            pager?NSStringFromCGRect(pager.bounds):@"none",
            pager?NSStringFromCGSize(pager.contentSize):@"none",
            pager?(!pager.tracking&&!pager.dragging&&!pager.decelerating):0,session!=nil);
        NFBLogWidgetHosts(root,0,&budget);
        UIView *content=window.rootViewController.view;
        for (NSUInteger depth=0;content&&depth<10;depth++,content=content.superview)
            if (content.hidden || content.alpha<0.01)
                NFBDebugLog(@"home-lock: %s hidden ancestor depth=%lu class=%@",phase,(unsigned long)depth,NSStringFromClass(content.class));
    }
}
void NFBObserveHomeWidgetLockDiagnostics(BOOL locked, BOOL enabled) {
    static BOOL known, previous;
    static NSUInteger epoch;
    BOOL changed=!known || previous!=locked;
    known=YES; previous=locked;
    if (!NFBDebugLoggingEnabled()) { epoch++; [widgetWatches removeAllObjects]; return; }
#ifndef NFB_DESKTOP_SIM_TEST
    NFBArmWidgetDetachTrace(changed && locked);
#endif
    if (!changed) return;
    NSUInteger current=++epoch;
    NFBDebugLog(@"home-lock: transition locked=%d enabled=%d epoch=%lu",locked,enabled,(unsigned long)current);
    if (locked) {
        NFBWidgetWatchSample("lock-edge");
    } else {
        NFBLogLockHomeWidgets("unlock");
        NFBWidgetWatchSample("unlock");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
            if (epoch!=current || previous || !NFBDebugLoggingEnabled()) return;
            NFBLogLockHomeWidgets("unlock+0.6");
            NFBWidgetWatchSample("unlock+0.6");
        });
    }
}

CGFloat NFBDesktopSplitCornerRadius(void) {
    return session && !session.restoring ? session.panel.layer.cornerRadius : NAN;
}
static UIScrollView *NFBFindIconPager(UIView *view) {
    if (view.hidden || view.alpha<0.01) return nil;
    NSString *name=NSStringFromClass(view.class);
    // SBFolderContainerView is also the HOME root's container. Rejecting every
    // name containing "Folder" prunes that entire branch before SBIconScrollView.
    // Exclude only real non-root folder views (including their subclasses).
    Class folderView=NSClassFromString(@"SBFolderView");
    Class rootFolderView=NSClassFromString(@"SBRootFolderView");
    BOOL rootFolder=[name containsString:@"RootFolder"] ||
        (rootFolderView && [view isKindOfClass:rootFolderView]);
    if (!rootFolder && folderView && [view isKindOfClass:folderView]) {
        NFBDebugLog(@"desktop-widget: pager search excludes open folder %@",name);
        return nil;
    }
    if ([view isKindOfClass:UIScrollView.class] && [name containsString:@"IconScroll"]) {
        NFBDebugLog(@"desktop-widget: pager found class=%@ parent=%@ bounds=%@ content=%@",
            name,NSStringFromClass(view.superview.class),NSStringFromCGRect(view.bounds),
            NSStringFromCGSize(((UIScrollView *)view).contentSize));
        return (UIScrollView *)view;
    }
    for (UIView *child in view.subviews) {
        UIScrollView *pager=NFBFindIconPager(child); if (pager) return pager;
    }
    return nil;
}
static UIScrollView *NFBDesktopPager(UIView *desktop) {
    UIScrollView *pager=NFBFindIconPager(desktop);
    if (pager) return pager;
    for (UIView *view in desktop.subviews)
        if (!view.hidden && view.alpha>=0.01 && [view isKindOfClass:UIScrollView.class] && [(UIScrollView *)view isPagingEnabled])
            return (UIScrollView *)view;
    return nil;
}
// On iOS 16 the launcher receives SBIconView for both apps and widgets.
// Check only this icon's subtree for the device-observed native widget hosts.
static BOOL NFBIsDesktopWidgetIconView(UIView *iconView) {
    Class container=NSClassFromString(@"SBHWidgetContainerView");
    Class host=NSClassFromString(@"CHUISWidgetHostViewControllerView");
    if (!container && !host) return NO;
    NSMutableArray<UIView *> *views=[NSMutableArray arrayWithObject:iconView];
    for (NSUInteger i=0;i<views.count;i++) {
        UIView *view=views[i];
        if ((container && [view isKindOfClass:container]) || (host && [view isKindOfClass:host])) return YES;
        for (UIView *child in view.subviews) {
            if (views.count>=64) break;
            [views addObject:child];
        }
    }
    return NO;
}
// An open request is not success: close only once Open reports the target pane.
BOOL NFBLaunchAppFromDesktopIcon(id iconView) {
    NFBDesktopSession *active=session;
    if (!active || active.restoring) return NO;
    if (![iconView isKindOfClass:UIView.class] || ![(UIView *)iconView isDescendantOfView:active.desktop]) return NO;
    id icon=NFBCheckedObject(iconView,@"icon");
    Class folderClass=NSClassFromString(@"SBFolderIcon");
    if (NFBCheckedBool(iconView,@"isFolderIcon",NO) || NFBCheckedBool(icon,@"isFolderIcon",NO) ||
        (folderClass && [icon isKindOfClass:folderClass])) {
        NFBDebugLog(@"desktop folder icon: native folder handling");
        return NO; // The hook calls the original folder handler; no app launch.
    }
    if (NFBIsDesktopWidgetIconView(iconView)) {
        NFBDebugLog(@"desktop widget icon: native launch handling");
        return NO; // Retain the original icon and actions, including widget URLs.
    }
    if (active.pendingApp.length) return YES;
    id bundle=NFBCheckedObject(iconView,@"applicationBundleIdentifier");
    if (![bundle isKindOfClass:NSString.class] || ![bundle length])
        bundle=NFBCheckedObject(icon,@"applicationBundleID");
    if (![bundle isKindOfClass:NSString.class] || ![bundle length])
        bundle=NFBCheckedObject(icon,@"applicationBundleIdentifier");
    if (![bundle isKindOfClass:NSString.class] || ![bundle length] || NFBIsSystemDesktop(bundle)) {
        NFBErrorLog(@"desktop split launch: no application identifier for %@",NSStringFromClass([iconView class]));
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"无法读取应用标识，桌面分屏已保留");
        return YES; // Never fall through to a fullscreen launch in the desktop pane.
    }
    [NFBSplitCoordinator.shared beginUserWindowOperation];
    active.pendingApp=bundle;
    active.pendingDeadline=CACurrentMediaTime()+8;
    NFBInvalidateWindowState();
    NFBWindowState *current=NFBCurrentWindowState();
    BOOL submitted=!current.home && [current.frontApp isEqualToString:bundle]
        ? NFBSplitTrollFrontmostApp() : NFBOpenTrollApp(bundle);
    if (!submitted) {
        active.pendingApp=nil;
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"应用分屏打开失败，桌面分屏已保留");
        NFBErrorLog(@"desktop split launch rejected: %@",bundle);
    }
    return YES;
}
static BOOL NFBDesktopAnimationsEnabled(void) {
    return UIView.areAnimationsEnabled && !UIAccessibilityIsReduceMotionEnabled();
}
// Read-only diagnostics: inspect actual child/layer state, not just the outer
// widget's hidden flag. Shared budget bounds work even on a large remote tree.
static void NFBLogWidgetContent(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!*budget || depth>4) return;
    --*budget;
    NFBDebugLog(@"desktop-widget-content: depth=%lu class=%@ hidden=%d alpha=%.2f attached=%d bounds=%@ layer=%@ layerHidden=%d opacity=%.2f sublayers=%lu hasContents=%d",
        (unsigned long)depth, NSStringFromClass(view.class), view.hidden, view.alpha, view.window!=nil,
        NSStringFromCGRect(view.bounds), NSStringFromClass(view.layer.class), view.layer.hidden,
        view.layer.opacity, (unsigned long)view.layer.sublayers.count, view.layer.contents!=nil);
    for (UIView *child in view.subviews) NFBLogWidgetContent(child,depth+1,budget);
}
// Read only ancestors: an invisible parent can blank an otherwise visible host.
static void NFBLogWidgetAncestors(UIView *view) {
    if (!NFBDebugLoggingEnabled()) return;
    NSUInteger depth=0;
    for (UIView *parent=view.superview; parent && depth<10; parent=parent.superview,depth++)
        NFBDebugLog(@"desktop-widget-ancestor: host=%p depth=%lu class=%@ hidden=%d alpha=%.2f layerHidden=%d opacity=%.2f bounds=%@ clips=%d mask=%@",
            view,(unsigned long)depth,NSStringFromClass(parent.class),parent.hidden,parent.alpha,
            parent.layer.hidden,parent.layer.opacity,NSStringFromCGRect(parent.bounds),parent.clipsToBounds,
            NSStringFromClass(parent.layer.mask.class));
}
static void NFBLogWidgetHosts(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (NFBDebugLoggingEnabled()) NFBTrackWidget(view);
    if (!*budget || depth>14) return;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"Widget"] || [name containsString:@"CHS"] ||
        [name containsString:@"RemoteView"] || [name containsString:@"Hosting"]) {
        --*budget;
        NFBDebugLog(@"desktop-widget: host=%@ view=%p hidden=%d alpha=%.2f window=%p frame=%@ children=%lu",
            name, view, view.hidden, view.alpha, view.window, NSStringFromCGRect(view.frame), (unsigned long)view.subviews.count);
        if ([name containsString:@"WidgetHost"] || [name containsString:@"RemoteView"])
            NFBLogWidgetContent(view,0,budget);
        if ([name containsString:@"WidgetHost"]) NFBLogWidgetAncestors(view);
    }
    for (UIView *child in view.subviews) NFBLogWidgetHosts(child,depth+1,budget);
}
static void NFBLogDesktopTouchTree(UIView *view, NSUInteger depth, NSUInteger *remaining) {
    if (!NFBDebugLoggingEnabled() || depth > 6 || !*remaining) return;
    --*remaining;
    NFBDebugLog(@"desktop touch tree: depth=%lu class=%@ hidden=%d alpha=%.2f interaction=%d bounds=%@ frame=%@ gestures=%lu",
        (unsigned long)depth, NSStringFromClass(view.class), view.hidden, view.alpha,
        view.userInteractionEnabled, NSStringFromCGRect(view.bounds), NSStringFromCGRect(view.frame),
        (unsigned long)view.gestureRecognizers.count);
    for (UIView *child in view.subviews) NFBLogDesktopTouchTree(child, depth+1, remaining);
}
// iOS 16.0.3 device logs show the private root wrapper returning itself for
// every icon/page touch. Only repair that observed blocker, within this session.
// Keep child hit testing native so hidden pages and overlapping views stay excluded.
static UIView *NFBDesktopRepairWrapperHit(UIView *hit, UIWindow *window, CGPoint point, UIEvent *event) {
    if (![NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"])
        return hit;
    for (UIView *child in hit.subviews.reverseObjectEnumerator) {
        UIView *candidate=[child hitTest:[child convertPoint:point fromView:window] withEvent:event];
        if (candidate) return candidate;
    }
    // Device tree shows this wrapper has no children or gestures. It may be a
    // frontmost layout sibling rather than the owner of the interactive content.
    // Search only siblings behind that branch, keeping their native hit tests.
    if (hit.subviews.count==0 && hit.gestureRecognizers.count==0) {
        UIView *branch=hit;
        while (branch && branch!=session.desktop) {
            UIView *parent=branch.superview;
            if (!parent || ![branch isDescendantOfView:session.desktop]) break;
            NSUInteger index=[parent.subviews indexOfObjectIdenticalTo:branch];
            if (index==NSNotFound) break;
            while (index>0) {
                UIView *sibling=parent.subviews[--index];
                UIView *candidate=[sibling hitTest:[sibling convertPoint:point fromView:window] withEvent:event];
                if (candidate && ![NSStringFromClass(candidate.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"])
                    return candidate;
            }
            branch=parent;
        }
    }
    return hit;
}
// A movie can be a sibling in the SAME native window as the hosted desktop.
// Returning nil for every point outside the pane skips that sibling entirely.
// Only offer actual Open floating windows; never expose the original home UI.
static UIView *NFBDesktopFloatingHit(UIView *view, UIView *panel, Class floatingClass,
                                    UIWindow *window, CGPoint point, UIEvent *event) {
    if (view == panel || view.hidden || view.alpha < 0.01 || !view.userInteractionEnabled) return nil;
    if ([view isKindOfClass:floatingClass]) {
        CGPoint local = [view convertPoint:point fromView:window];
        if (![view pointInside:local withEvent:event]) return nil;
        return [view hitTest:local withEvent:event];
    }
    NSArray *children = [[view.subviews reverseObjectEnumerator].allObjects
        sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            if (a.layer.zPosition > b.layer.zPosition) return NSOrderedAscending;
            if (a.layer.zPosition < b.layer.zPosition) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    for (UIView *child in children) {
        UIView *hit = NFBDesktopFloatingHit(child, panel, floatingClass, window, point, event);
        if (hit) return hit;
    }
    return nil;
}
// A separate Open host must remain above the elevated desktop window. While
// borrowed, only native floating-app descendants may accept touches; its empty
// full-screen root must not shield the lower desktop. Never return a view from
// another UIWindow and never synthesize/redispatch UIEvents.
static NFBWindowLease *NFBMovieHostLease(void) { return NFBSplitCoordinator.shared.windowLease; }
#ifndef NFB_DESKTOP_SIM_TEST
static Class movieHostHitClass;
static UIView *(*originalMovieHostHit)(id, SEL, CGPoint, UIEvent *);
static UIView *NFBMovieHostHit(id object, SEL selector, CGPoint point, UIEvent *event) {
    if (session && !session.restoring && [NFBMovieHostLease() ownsHost:object session:session.identifier]) {
        @try {
            return [NFBMovieHostLease() nativeHitInHost:object point:point event:event session:session.identifier];
        } @catch (NSException *error) {
            NFBErrorLog(@"movie-touch: host hit exception %@", error);
            return nil;
        }
    }
    return originalMovieHostHit(object, selector, point, event);
}
#endif
void NFBUpdateMovieDesktopTouchHosts(NSArray<UIWindow *> *hosts) {
    if (!NSThread.isMainThread) return;
    if (!session || session.restoring) {
        [NFBMovieHostLease() releaseSession:NFBMovieHostLease().sessionIdentifier]; return;
    }
    NSMutableArray<UIWindow *> *eligible=[NSMutableArray array];
    for (UIWindow *host in hosts) {
        if (host==session.window) continue;
#ifndef NFB_DESKTOP_SIM_TEST
        Class cls=object_getClass(host);
        if (!movieHostHitClass) {
            Method method=class_getInstanceMethod(cls,@selector(hitTest:withEvent:));
            Method base=class_getInstanceMethod(UIWindow.class,@selector(hitTest:withEvent:));
            if (!method || strcmp(method_getTypeEncoding(method),method_getTypeEncoding(base))) continue;
            MSHookMessageEx(cls,@selector(hitTest:withEvent:),(IMP)NFBMovieHostHit,(IMP *)&originalMovieHostHit);
            movieHostHitClass=cls;
        }
        if (cls!=movieHostHitClass || !originalMovieHostHit) continue;
#endif
        [eligible addObject:host];
    }
    [NFBMovieHostLease() updateHosts:eligible desktop:session.window session:session.identifier];
}
void NFBPublishMovieTouchWindows(NSArray<UIView *> *windows, NSUInteger desktopSession) {
    if (!NSThread.isMainThread || !session || session.restoring || session.identifier!=desktopSession) return;
    [NFBMovieHostLease() publishTouchWindows:windows session:desktopSession];
}
// Use the native home window: its controller and scene remain the desktop owners.
// This helper is also exercised by the simulator window fixture.
UIView *NFBDesktopSplitHitTest(UIWindow *window, CGPoint point, UIEvent *event, BOOL *handled) {
    NFBDesktopSession *active = session;
    *handled = active && !active.restoring && active.window == window;
    if (!*handled) return nil;
    if (active.movieParked) {
        // Shared host may contain Open roots: route those only, never hidden home.
        Class floatingClass=NFBTrollFloatingWindowClass();
        return floatingClass ? NFBDesktopFloatingHit(window,active.panel,floatingClass,window,point,event) : nil;
    }
    CGPoint local = [active.panel convertPoint:point fromView:window];
    if (![active.panel pointInside:local withEvent:event]) {
        Class floatingClass = NFBTrollFloatingWindowClass();
        UIView *hit = floatingClass ? NFBDesktopFloatingHit(window, active.panel, floatingClass, window, point, event) : nil;
        if (event && NFBDebugLoggingEnabled()) {
            static CFTimeInterval lastOutsideLog;
            CFTimeInterval now = CACurrentMediaTime();
            if (now - lastOutsideLog > 0.5) {
                lastOutsideLog = now;
                NFBDebugLog(@"movie-touch: outside point=%@ desktopWindow=%p class=%@ level=%.1f key=%d hit=%@ hitWindow=%p panel=%@",
                    NSStringFromCGPoint(point), window, NSStringFromClass(window.class), window.windowLevel,
                    window.isKeyWindow, NSStringFromClass(hit.class), hit.window, NSStringFromCGRect(active.panel.frame));
                for (UIWindow *candidate in NFBDesktopWindows()) {
                    NFBDebugLog(@"movie-touch: window=%p class=%@ level=%.1f hidden=%d alpha=%.2f interaction=%d key=%d",
                        candidate, NSStringFromClass(candidate.class), candidate.windowLevel, candidate.hidden,
                        candidate.alpha, candidate.userInteractionEnabled, candidate.isKeyWindow);
                }
            }
        }
        return hit; // Diagnostics only: preserve the existing routing exactly.
    }
    if (active.refreshScroll) return active.panel;
    // Activating swaps the key window and BFS-scans the desktop subtree. Doing it
    // inside hit-test changes the responder chain mid-dispatch and stalls the
    // first touch; hand it to the next runloop turn instead.
    if (event) {
        // A real touch wins over a pending automatic page visit. In-flight
        // roundtrips already returned the panel above and finish in 0.1s.
        active.widgetRefreshCancelled = YES;
        static NSUInteger scheduledActivation;
        if (!scheduledActivation) {
            scheduledActivation++;
            NSUInteger activationSession=active.identifier;
            dispatch_async(dispatch_get_main_queue(), ^{
                scheduledActivation = 0;
                NFBDesktopSession *current = session;
                if (current && current.identifier==activationSession && !current.restoring && current.window == window) [current activateDesktop];
            });
        }
    }
    UIView *hit = [active.panel hitTest:local withEvent:event];
    UIView *originalHit=hit;
    hit=NFBDesktopRepairWrapperHit(hit,window,point,event);
    if ([NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"]) {
        // A freshly exposed page may contain new disabled descendants. Repair
        // that observed miss immediately rather than waiting for the next scan.
        active.lastInteractionScan=0; [active adoptDesktopInteraction];
        hit=[active.panel hitTest:local withEvent:event];
        hit=NFBDesktopRepairWrapperHit(hit,window,point,event);
    }
    if (NFBDebugLoggingEnabled()) {
        if (hit!=originalHit)
            NFBDebugLog(@"desktop wrapper route: %@ -> %@",NSStringFromClass(originalHit.class),NSStringFromClass(hit.class));
        else if ([NSStringFromClass(hit.class) isEqualToString:@"_SBRootFolderLayoutWrapperView"] && active.blockedHitReports++ < 2) {
            NSUInteger remaining=80; NFBLogDesktopTouchTree(active.desktop,0,&remaining);
        }
        NFBDebugLog(@"desktop native hit: %@",hit ? NSStringFromClass(hit.class) : @"nil");
    }
    return hit;
}
// Device traces show this close-only match-move animation displacing the
// folder container while its model geometry and the pane host stay fixed.
// Its screen-space tracking is invalid after transplanting the native desktop.
// Preserve all native scale/opacity animations and the ordinary home screen.
BOOL NFBDesktopSuppressFolderTracking(CALayer *layer, NSString *key) {
    NFBDesktopSession *active=session;
    if (!NSThread.isMainThread || !active || active.restoring ||
        ![key isEqualToString:@"SBFolderSourceViewTrackingMatchMoveAnimation"]) return NO;
    Class containerClass=NSClassFromString(@"SBFolderContainerView");
    id owner=layer.delegate;
    if (!containerClass || ![owner isKindOfClass:containerClass] ||
        ![owner isKindOfClass:UIView.class] || [(UIView *)owner layer]!=layer ||
        ![(UIView *)owner isDescendantOfView:active.desktop]) return NO;
    for (CALayer *ancestor=layer; ancestor; ancestor=ancestor.superlayer)
        if (ancestor==active.desktop.layer) return YES;
    return NO;
}
#ifndef NFB_DESKTOP_SIM_TEST
static void (*originalDesktopAddAnimation)(CALayer *, SEL, CAAnimation *, NSString *);
static void NFBDesktopAddAnimation(CALayer *layer, SEL selector, CAAnimation *animation, NSString *key) {
    if (NFBDesktopSuppressFolderTracking(layer,key)) {
        NFBDebugLog(@"desktop folder close: bypass screen-space source tracking");
        return;
    }
    originalDesktopAddAnimation(layer,selector,animation,key);
}
static void NFBInstallDesktopFolderAnimationHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        MSHookMessageEx(CALayer.class,@selector(addAnimation:forKey:),(IMP)NFBDesktopAddAnimation,(IMP *)&originalDesktopAddAnimation);
    });
}
#endif
#ifndef NFB_DESKTOP_SIM_TEST
static Class desktopHitClass;
static UIView *(*originalDesktopHitTest)(id, SEL, CGPoint, UIEvent *);
static UIView *NFBDesktopNativeHitTest(id object, SEL selector, CGPoint point, UIEvent *event) {
    // Touch path: an exception escaping here unwinds through UIKit's event
    // dispatch and kills SpringBoard. Always fall back to the native result.
    BOOL handled = NO;
    @try {
        UIView *hit = NFBDesktopSplitHitTest(object, point, event, &handled);
        if (handled) return hit;
    } @catch (NSException *error) {
        NFBErrorLog(@"desktop hit test failed: %@", error);
    }
    return originalDesktopHitTest(object, selector, point, event);
}
static BOOL NFBInstallDesktopHitHook(UIWindow *window) {
    Class cls = object_getClass(window);
    if (desktopHitClass) return cls == desktopHitClass && originalDesktopHitTest != NULL;
    Method method = class_getInstanceMethod(cls, @selector(hitTest:withEvent:));
    if (!method) return NO;
    NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (sig.numberOfArguments!=4 || sig.methodReturnType[0]!='@' ||
        strcmp([sig getArgumentTypeAtIndex:2],@encode(CGPoint)) || [sig getArgumentTypeAtIndex:3][0]!='@') return NO;
    // Hook the actual system window class, including its private hit-test override.
    MSHookMessageEx(cls, @selector(hitTest:withEvent:), (IMP)NFBDesktopNativeHitTest,
                   (IMP *)&originalDesktopHitTest);
    desktopHitClass = cls;
    return originalDesktopHitTest != NULL;
}
#endif
static NSString *lastFailure;
static BOOL failurePending;
NSString *NFBDesktopSplitError(void) { return lastFailure ?: @"桌面分屏打开失败"; }
NSString *NFBConsumeDesktopSplitFailure(void) {
    if (!failurePending) return nil;
    failurePending = NO;
    return NFBDesktopSplitError();
}
static BOOL NFBDesktopFail(NSString *reason) {
    lastFailure = reason;
    NFBErrorLog(@"desktop split: %@", reason);
    return NO;
}

static NSArray<UIWindow *> *NFBDesktopWindows(void) {
    NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    return windows.array;
}
static BOOL NFBDesktopContainsFloating(UIView *view) {
    Class floating = NFBTrollFloatingWindowClass();
    if (floating && [view isKindOfClass:floating]) return YES;
    for (UIView *child in view.subviews) if (NFBDesktopContainsFloating(child)) return YES;
    return NO;
}
static BOOL NFBDesktopContainsRootFolder(UIView *view) {
    Class root = NSClassFromString(@"SBRootFolderView");
    if (root && [view isKindOfClass:root]) return YES;
    for (UIView *child in view.subviews) if (NFBDesktopContainsRootFolder(child)) return YES;
    return NO;
}
static BOOL NFBDesktopEligible(UIView *view, UIView *anchor) {
    return [view isKindOfClass:UIView.class] && view.superview && ![view isKindOfClass:UIWindow.class] &&
        view != anchor && ![anchor isDescendantOfView:view] && ![view isDescendantOfView:anchor] &&
        NFBDesktopContainsRootFolder(view) && !NFBDesktopContainsFloating(view) &&
        CGRectGetWidth(view.bounds) > 0 && CGRectGetHeight(view.bounds) > 0 &&
        isfinite(CGRectGetWidth(view.bounds)) && isfinite(CGRectGetHeight(view.bounds));
}
static UIView *NFBDesktopFromController(UIViewController *controller, UIView *anchor) {
    if (!controller.isViewLoaded) return nil;
    Class home = NSClassFromString(@"SBHomeScreenViewController");
    if (home && [controller isKindOfClass:home] && NFBDesktopEligible(controller.view, anchor)) return controller.view;
    for (UIViewController *child in controller.childViewControllers) {
        UIView *found = NFBDesktopFromController(child, anchor);
        if (found) return found;
    }
    return nil;
}
static UIView *NFBDesktopContentInTree(UIView *view, UIView *anchor) {
    Class content = NSClassFromString(@"SBIconContentView");
    if (content && [view isKindOfClass:content] && NFBDesktopEligible(view, anchor)) {
        // Never settle for just the icon list: include sibling dock/folder hosts.
        UIView *candidate = view;
        for (UIView *parent=view.superview; parent && ![parent isKindOfClass:UIWindow.class]; parent=parent.superview) {
            if (!NFBDesktopEligible(parent, anchor)) break;
            candidate=parent;
        }
        return candidate;
    }
    for (UIView *child in view.subviews) {
        UIView *found = NFBDesktopContentInTree(child, anchor);
        if (found) return found;
    }
    return nil;
}
// Last-resort lookup, used only after the controller and icon-content routes have
// failed: scan a window for a root folder view and keep its outermost eligible
// ancestor. Covers the case where the desktop is still on screen but no longer
// reachable through the view controller that used to own it.
static UIView *NFBDesktopFromTree(UIView *view, UIView *anchor) {
    Class root = NSClassFromString(@"SBRootFolderView");
    if (root && [view isKindOfClass:root]) {
        UIView *candidate = nil;
        for (UIView *ancestor = view; ancestor && ![ancestor isKindOfClass:UIWindow.class]; ancestor = ancestor.superview) {
            if (!NFBDesktopEligible(ancestor, anchor)) break;
            candidate = ancestor;
        }
        if (candidate) return candidate;
        return NFBDesktopEligible(view, anchor) ? view : nil;
    }
    for (UIView *child in view.subviews) {
        UIView *found = NFBDesktopFromTree(child, anchor);
        if (found) return found;
    }
    return nil;
}
static UIView *NFBDesktopSource(UIView *anchor) {
    NSArray<UIWindow *> *windows=NFBDesktopWindows();
    // Prefer the complete home controller (dock and folder presentation included).
    for (UIWindow *window in windows) {

        UIView *view = NFBDesktopFromController(window.rootViewController, anchor);
        if (view) return view;
    }
    id icons = NFBCheckedObject(NSClassFromString(@"SBIconController"), @"sharedInstance");
    if ([icons isKindOfClass:UIViewController.class] && [(UIViewController *)icons isViewLoaded]) {
        UIView *view = [(UIViewController *)icons view];
        if (NFBDesktopEligible(view, anchor)) return view;
    }
    for (UIWindow *window in windows) {

        UIView *view = NFBDesktopContentInTree(window, anchor);
        if (view) return view;
    }
    // Fullscreen apps can hide or detach the desktop's original window. Resolve
    // the already loaded root through the native singleton as well as windows.
    id manager = NFBCheckedObject(icons, @"iconManager");
    for (id owner in @[icons ?: NSNull.null, manager ?: NSNull.null]) {
        for (NSString *name in @[@"rootFolderController", @"_rootFolderController"]) {
            id controller = NFBCheckedObject(owner, name);
            if (![controller isKindOfClass:UIViewController.class] || ![(UIViewController *)controller isViewLoaded]) continue;
            UIView *view = [(UIViewController *)controller view];
            UIView *candidate = nil;
            for (UIView *ancestor = view; ancestor && ![ancestor isKindOfClass:UIWindow.class]; ancestor = ancestor.superview) {
                if (!NFBDesktopEligible(ancestor, anchor)) break;
                candidate = ancestor;
            }
            if (candidate) return candidate;
        }
    }
    for (UIWindow *window in windows) {
        UIView *view = NFBDesktopFromTree(window, anchor);
        if (view) {
            NFBErrorLog(@"desktop source resolved by hierarchy scan in %@", NSStringFromClass(window.class));
            return view;
        }
    }
    NFBErrorLog(@"desktop source missing: icons=%@ manager=%@", NSStringFromClass([icons class]), NSStringFromClass([manager class]));
    return nil;
}
static UIView *NFBConstraintView(id item) {
    if ([item isKindOfClass:UIView.class]) return item;
    if ([item isKindOfClass:UILayoutGuide.class]) return [(UILayoutGuide *)item owningView];
    return nil;
}
static BOOL NFBInsideDesktop(UIView *item, UIView *desktop) {
    return item && (item == desktop || [item isDescendantOfView:desktop]);
}
static NSArray<NSLayoutConstraint *> *NFBDesktopExternalConstraints(UIView *desktop) {
    NSMutableArray *result = [NSMutableArray array];
    for (UIView *parent = desktop.superview; parent; parent = parent.superview)
        for (NSLayoutConstraint *constraint in parent.constraints) {
            BOOL first = NFBInsideDesktop(NFBConstraintView(constraint.firstItem), desktop);
            BOOL second = NFBInsideDesktop(NFBConstraintView(constraint.secondItem), desktop);
            if (constraint.active && first != second) [result addObject:constraint];
        }
    return result;
}
static BOOL NFBDesktopLocked(void) {
    id lock = NFBCheckedObject(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance");
    return NFBCheckedBool(lock, @"isUILocked", YES);
}
// The transplanted desktop keeps its icons, folders and widgets: moving the view
// into the pane is what leaves the original home screen showing only its
// wallpaper. What does need help is that SpringBoard hides the home screen's
// content - and its wallpaper - while a fullscreen app is in front, which left
// the pane completely blank. Only the content containers and the wallpaper are
// revealed here, and every change is undone when the pane closes. Individual page
// icon lists are deliberately left alone: only the current page should show.
static BOOL NFBIsDesktopRevealClass(NSString *name) {
    return [name containsString:@"Wallpaper"] || [name containsString:@"SBRootFolder"] ||
        [name containsString:@"IconContent"];
}
static void NFBCollectRevealViews(UIView *view, NSMutableArray<UIView *> *reveal, NSMutableArray<UIView *> *wallpaper) {
    for (UIView *child in view.subviews) {
        NSString *name = NSStringFromClass(child.class);
        BOOL isWallpaper = [name containsString:@"Wallpaper"];
        if (isWallpaper) [wallpaper addObject:child];
        if ((isWallpaper || NFBIsDesktopRevealClass(name)) && (child.hidden || child.alpha < 1))
            [reveal addObject:child];
        NFBCollectRevealViews(child, reveal, wallpaper);
    }
}
static void NFBCountHiddenViews(UIView *view, NSUInteger *count) {
    for (UIView *child in view.subviews) {
        if (child.hidden || child.alpha < 0.01) (*count)++;
        NFBCountHiddenViews(child, count);
    }
}
static UIView *NFBWallpaperInTree(UIView *view) {
    if ([NSStringFromClass(view.class) containsString:@"Wallpaper"] &&
        !view.hidden && view.alpha > 0.01 && CGRectGetWidth(view.bounds) > 1 && CGRectGetHeight(view.bounds) > 1)
        return view;
    for (UIView *child in view.subviews) {
        UIView *found = NFBWallpaperInTree(child);
        if (found) return found;
    }
    return nil;
}
static UIView *NFBSystemWallpaperView(UIWindow *excluding) {
    for (UIWindow *window in NFBDesktopWindows()) {
        if (window == excluding || window.hidden) continue;
        UIView *found = NFBWallpaperInTree(window);
        if (found) return found;
    }
    return nil;
}
@implementation NFBDesktopSession
- (void)finishWidgetRefresh {
    UIScrollView *pager=self.refreshScroll; CGPoint offset=self.refreshOffset;
    NFBAttemptCleanup(@"widget page offset", ^{
        if (pager) [UIView performWithoutAnimation:^{ [pager setContentOffset:offset animated:NO]; [pager layoutIfNeeded]; }];
    });
    self.refreshScroll=nil;
    NFBAttemptCleanup(@"widget cover", ^{ [self.refreshCover removeFromSuperview]; }); self.refreshCover=nil;
}
- (void)scheduleWidgetRefreshRetry {
    if (self.widgetRefreshAttempts >= 6 || self.widgetRefreshFinished || self.widgetRefreshCancelled) {
        NFBDebugLog(@"desktop-widget: bounded refresh stopped attempts=%lu cancelled=%d done=%d",
            (unsigned long)self.widgetRefreshAttempts,self.widgetRefreshCancelled,self.widgetRefreshFinished);
        return;
    }
    __weak NFBDesktopSession *weakSession=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.2*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        NFBDesktopSession *active=weakSession;
        if (!active || session!=active || active.restoring || active.widgetRefreshCancelled ||
            active.widgetRefreshFinished || active.pendingApp.length) return;
        [active refreshWidgetPage];
    });
}
- (void)refreshWidgetPage {
    @try {
    if (session!=self || self.restoring || self.widgetRefreshCancelled || self.pendingApp.length ||
        self.widgetRefreshFinished || self.refreshScroll) {
        NFBDebugLog(@"desktop-widget: refresh skipped session=%d restoring=%d startedHome=%d pending=%d",
            session==self, self.restoring, self.startedHome, self.pendingApp.length>0);
        return;
    }
    if (self.widgetRefreshAttempts >= 6) return;
    self.widgetRefreshAttempts++;
    UIScrollView *pager=NFBDesktopPager(self.desktop);
    if (pager && (pager.tracking || pager.dragging || pager.decelerating)) {
        self.widgetRefreshCancelled=YES;
        NFBDebugLog(@"desktop-widget: refresh cancelled for user scroll"); return;
    }
    if (!pager) {
        NFBDebugLog(@"desktop-widget: waiting for pager attempt=%lu",(unsigned long)self.widgetRefreshAttempts);
        [self scheduleWidgetRefreshRetry]; return;
    }
    if (pager.contentSize.width<pager.bounds.size.width*2 || pager.bounds.size.width<=0) {
        NFBDebugLog(@"desktop widget refresh: only one reachable page; no page roundtrip");
        [self scheduleWidgetRefreshRetry]; return;
    }
    CGPoint original=pager.contentOffset;
    CGFloat width=pager.bounds.size.width;
    CGFloat minimum=-pager.adjustedContentInset.left;
    CGFloat maximum=pager.contentSize.width-width+pager.adjustedContentInset.right;
    CGFloat target=original.x+width<=maximum+0.5 ? MIN(maximum,original.x+width) : MAX(minimum,original.x-width);
    // Never snap an intermediate user/page-animation position back to a page.
    CGFloat page=(original.x-minimum)/width;
    if (!isfinite(page) || fabs(page-round(page))>0.01 || fabs(target-original.x)<width*0.5) {
        [self scheduleWidgetRefreshRetry]; return;
    }
    UIView *cover=[self.canvas snapshotViewAfterScreenUpdates:NO];
    if (!cover) {
        // A newly attached host may not yet have a compositor snapshot.
        // Render the existing layer tree as a cover without forcing a screen
        // update or giving up the page refresh altogether.
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.canvas.bounds];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [self.canvas.layer renderInContext:context.CGContext];
        }];
        if (image) cover=[[UIImageView alloc] initWithImage:image];
    }
    if (!cover) {
        NFBErrorLog(@"desktop widget refresh: both cover capture paths failed; page preserved");
        [self scheduleWidgetRefreshRetry]; return;
    }
    self.widgetRefreshFinished=YES; // At most one roundtrip per session.
    self.refreshScroll=pager; self.refreshOffset=original;
    NFBDebugLog(@"desktop-widget: roundtrip begin attempt=%lu pager=%@ original=%@ target=%.2f startedHome=%d",
        (unsigned long)self.widgetRefreshAttempts,NSStringFromClass(pager.class),NSStringFromCGPoint(original),target,self.startedHome);
    cover.frame=self.canvas.bounds; cover.userInteractionEnabled=NO;
    self.refreshCover=cover; if (cover) [self.canvas addSubview:cover];
    // Reproduce the device-proven page exit/reentry, with the original page
    // covered and its exact offset restored before exposing the refreshed pane.
    [UIView performWithoutAnimation:^{
        [pager setContentOffset:CGPointMake(target,original.y) animated:NO];
        [pager layoutIfNeeded];
    }];
    __weak NFBDesktopSession *weakSession=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.1*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        NFBDesktopSession *active=weakSession;
        if (!active || session!=active || active.restoring) return;
        // If native scrolling acquired the pager during the covered visit,
        // never overwrite the user's new position.
        if (pager.tracking || pager.dragging || pager.decelerating) active.refreshScroll=nil;
        [active finishWidgetRefresh];
        NFBDebugLog(@"desktop widget page refresh: restored %@ offset=%@",NSStringFromClass(pager.class),NSStringFromCGPoint(original));
    });
    } @catch (NSException *error) {
        [self finishWidgetRefresh]; NFBErrorLog(@"desktop widget refresh failed: %@",error);
    }
}
- (void)activateDesktop {
    if (self.restoring || self.movieParked) return;
    [self adoptDesktopInteraction];
    if (!self.window.isKeyWindow) [self.window makeKeyWindow];
}
- (void)rememberAppearance:(UIView *)view {
    if (!self.appearanceState) self.appearanceState=[NFBStateLedger new];
    BOOL hidden=view.hidden; CGFloat alpha=view.alpha;
    [self.appearanceState remember:view key:@"appearance" restore:^{ view.hidden=hidden; view.alpha=alpha; }];
}
- (void)adoptDesktopAppearance {
    NSMutableArray<UIView *> *reveal = [NSMutableArray array];
    NSMutableArray<UIView *> *wallpaper = [NSMutableArray array];
    NFBCollectRevealViews(self.desktop, reveal, wallpaper);
    for (UIView *view in reveal) {
        [self rememberAppearance:view];
        view.hidden = NO;
        view.alpha = 1;
    }
    self.wallpaperCount = wallpaper.count;
    if (NFBDebugLoggingEnabled()) {
        NSUInteger hidden=0; NFBCountHiddenViews(self.desktop,&hidden);
        NFBDebugLog(@"desktop pane: revealed %lu view(s), wallpaper=%lu, still hidden=%lu",
            (unsigned long)reveal.count,(unsigned long)wallpaper.count,(unsigned long)hidden);
    }
}
- (void)restoreDesktopAppearance { [self.appearanceState restore]; self.appearanceState=nil; }
- (void)installPaneBackdrop {
    // The desktop subtree carries no wallpaper of its own, so borrow one: a
    // snapshot of the live system wallpaper when it is on screen, otherwise a
    // material, so the pane never shows a bare light background.
    UIView *backdrop = nil;
    UIView *wallpaper = NFBSystemWallpaperView(self.window);
    if (wallpaper) {
        UIView *snapshot = [wallpaper snapshotViewAfterScreenUpdates:NO];
        if (snapshot) {
            snapshot.frame = self.canvas.bounds;
            snapshot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            snapshot.userInteractionEnabled = NO;
            backdrop = snapshot;
        }
    }
    if (!backdrop) {
        UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        material.frame = self.canvas.bounds;
        material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        backdrop = material;
    }
    backdrop.userInteractionEnabled = NO;
    [self.canvas insertSubview:backdrop atIndex:0];
    NFBDebugLog(@"desktop pane: backdrop installed (%@)", NSStringFromClass(backdrop.class));
}
- (void)adoptDesktopInteraction {
    if (!self.interactionState) self.interactionState=[NFBStateLedger new];
    CFTimeInterval now=CACurrentMediaTime();
    // Keep the fast touch repair on known paths; discover newly visible pages at
    // most every 0.25 seconds, independent of the manager's multiple callers.
    if (!self.knownInteractiveViews || now-self.lastInteractionScan>=0.25) {
        self.lastInteractionScan=now;
        self.knownInteractiveViews=[NSHashTable weakObjectsHashTable];
        NSMutableArray<UIView *> *stack=[NSMutableArray arrayWithObject:self.desktop];
        while (stack.count) {
            UIView *view=stack.lastObject; [stack removeLastObject];
            if (view.hidden || view.alpha<0.01) continue;
            [stack addObjectsFromArray:view.subviews];
            if ([view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UIControl.class] ||
                [NSStringFromClass(view.class) containsString:@"IconView"] || view.gestureRecognizers.count)
                [self.knownInteractiveViews addObject:view];
        }
    }
    for (UIView *view in self.knownInteractiveViews.allObjects) {
        if (![view isDescendantOfView:self.desktop] || view.hidden || view.alpha<0.01) continue;
        BOOL visible=YES;
        for (UIView *ancestor=view; ancestor && ancestor!=self.canvas; ancestor=ancestor.superview)
            if (ancestor.hidden || ancestor.alpha<0.01) { visible=NO; break; }
        if (!visible) continue;
        for (UIView *ancestor=view; ancestor && ancestor!=self.canvas; ancestor=ancestor.superview) {
            if (!ancestor.userInteractionEnabled) {
                [self.interactionState remember:ancestor key:@"interaction" restore:^{ ancestor.userInteractionEnabled=NO; }];
                ancestor.userInteractionEnabled=YES;
            }
        }
        if ([view isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll=(UIScrollView *)view; BOOL enabled=scroll.scrollEnabled;
            [self.interactionState remember:scroll key:@"scroll" restore:^{ scroll.scrollEnabled=enabled; }];
            if (!enabled) scroll.scrollEnabled=YES;
        }
        for (UIGestureRecognizer *gesture in view.gestureRecognizers)
            if (!gesture.enabled && ([gesture isKindOfClass:UITapGestureRecognizer.class] ||
                ([view isKindOfClass:UIScrollView.class] && gesture==[(UIScrollView *)view panGestureRecognizer]))) {
                [self.interactionState remember:gesture key:@"gesture" restore:^{ gesture.enabled=NO; }];
                gesture.enabled=YES;
            }
    }
}
- (void)restoreDesktopInteraction {
    [self.interactionState restore]; self.interactionState=nil; self.knownInteractiveViews=nil;
}
- (BOOL)place {
    UIWindow *window = self.window;
    CGRect screen = window.bounds;
    if (CGRectGetWidth(screen) >= CGRectGetHeight(screen)) return NFBDesktopFail(@"桌面分屏目前仅支持竖屏");
    if (!self.placed) {
        UIView *anchor = self.anchor;
        if (!anchor.window) return NFBDesktopFail(@"原分屏窗口已关闭");
        // The pane reproduces the split app pane exactly: same size, same position.
        // The anchor is itself a window, so convert straight into the pane window; a
        // window-to-itself conversion would silently drop the origin.
        CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:window];
        if (!isfinite(anchorFrame.origin.x) || !isfinite(anchorFrame.origin.y) ||
            !isfinite(CGRectGetWidth(anchorFrame)) || !isfinite(CGRectGetHeight(anchorFrame)) ||
            CGRectGetWidth(anchorFrame) < 120 || CGRectGetHeight(anchorFrame) < 180)
            return NFBDesktopFail(@"原分屏窗口尺寸无效");
        self.panelFrame = anchorFrame;
        self.placed = YES;
    }
    CGRect frame = self.panelFrame;
    frame.origin.x = MAX(CGRectGetMinX(screen), MIN(frame.origin.x, CGRectGetMaxX(screen)-frame.size.width));
    frame.origin.y = MAX(CGRectGetMinY(screen), MIN(frame.origin.y, CGRectGetMaxY(screen)-frame.size.height));
    self.panelFrame = frame;
    // The session's existing safety timer runs place: updates apply in both
    // modes without reopening, resizing or rebuilding the desktop.
    CGFloat radius = 14.0;
    if (fabs(self.panel.layer.cornerRadius-radius) > 0.001) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        self.panel.layer.cornerRadius = radius;
        [CATransaction commit];
    }
    CGRect panelBounds = CGRectMake(0,0,frame.size.width,frame.size.height);
    CGPoint panelCenter = CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    if (!CGRectEqualToRect(self.panel.bounds,panelBounds)) self.panel.bounds = panelBounds;
    if (!CGPointEqualToPoint(self.panel.center,panelCenter)) self.panel.center = panelCenter;
    // The wallpaper and native desktop fill the whole pane.
    if (!CGRectEqualToRect(self.canvas.frame,self.panel.bounds)) self.canvas.frame = self.panel.bounds;
    double scale = NFBDesktopScale(CGRectGetWidth(self.originalBounds), CGRectGetHeight(self.originalBounds),
        CGRectGetWidth(self.canvas.bounds),CGRectGetHeight(self.canvas.bounds));
    if (!(scale > 0)) return NFBDesktopFail(@"桌面尺寸无效");
    // Keep SpringBoard's desktop in native coordinates. Only this outer host
    // owns the pane transform; folder transitions may animate desktop geometry.
    UIView *host = self.desktopHost;
    CGPoint center = CGPointMake(CGRectGetMidX(self.canvas.bounds),CGRectGetMidY(self.canvas.bounds));
    CGAffineTransform transform = CGAffineTransformMakeScale(scale,scale);
    if (!CGRectEqualToRect(host.bounds,self.originalBounds)) host.bounds = self.originalBounds;
    if (!CGPointEqualToPoint(host.center,center)) host.center = center;
    if (!CGAffineTransformEqualToTransform(host.transform,transform)) host.transform = transform;
    return YES;
}
- (void)check {
    if (session != self || self.restoring || self.mutationPhase != NFBDesktopMutationActive) return;
    // 10 Hz timer. Every other private-API path in this file is wrapped; this one
    // was not, so a single throw here terminated SpringBoard.
    @try { [self checkBody]; }
    @catch (NSException *error) {
        NFBErrorLog(@"desktop split check failed: %@", error);
        failurePending = YES; NFBCloseDesktopSplit();
    }
}
- (void)checkBody {
    if (NFBDesktopLocked()) {
        NFBCloseDesktopSplit(); return;
    }
    if (self.pendingApp.length) {
        NFBInvalidateWindowState();
        NFBWindowState *state=NFBCurrentWindowState();
        if ([state.floatingApp isEqualToString:self.pendingApp] && state.floatingWindow && !state.mini) {
            NFBDebugLog(@"desktop split launch visible: %@",self.pendingApp);
            if (self.moviePersistent) {
                NFBSetMovieDesktopParked(self.identifier, YES);
            } else { NFBCloseDesktopSplit(); return; }
        }
        if (self.pendingApp.length && CACurrentMediaTime()>=self.pendingDeadline) {
            NFBErrorLog(@"desktop split launch timed out: %@",self.pendingApp);
            self.pendingApp=nil;
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,@"尚未确认应用分屏打开，桌面分屏已保留");
        }
    }
    if (self.desktop.superview != self.desktopHost || ![self place]) {
        if (self.desktop.superview != self.desktopHost) NFBDesktopFail(@"系统重新调整了桌面视图，已恢复桌面");
        failurePending = YES; NFBCloseDesktopSplit();
        return;
    }
    if (self.window.hidden || self.window.alpha < 0.01) {
        NFBDesktopFail(@"系统隐藏了原生桌面窗口，已恢复桌面");
        failurePending = YES; NFBCloseDesktopSplit(); return;
    }
    // A parked desktop must not re-enable hidden content or claim interaction.
    if (self.movieParked) return;
    if (self.moviePersistent && (self.desktop.hidden || self.desktop.alpha<0.01)) {
        NFBDebugLog(@"movie-desktop: repair hosted content visibility");
        [UIView performWithoutAnimation:^{
            self.desktop.hidden=NO;
            self.desktop.alpha=1;
            [self adoptDesktopAppearance];
        }];
    }
    // Repair native interaction changes without overwriting the original state.
    [self adoptDesktopInteraction];
}
static void NFBLogHomeReturn(NSString *phase, NSUInteger identifier, UIView *desktop) {
    if (!desktop || !NFBDebugLoggingEnabled()) return;
    UIWindow *window=desktop.window;
    NFBDebugLog(@"home-return: %@ session=%lu window=%p level=%.1f hidden=%d alpha=%.2f key=%d",phase,(unsigned long)identifier,window,window.windowLevel,window.hidden,window.alpha,window.isKeyWindow);
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:desktop];
    NSUInteger logged=0;
    for (NSUInteger i=0;i<queue.count && i<128 && logged<10;i++) {
        UIView *view=queue[i];
        NSString *name=NSStringFromClass(view.class);
        if (i==0 || [name containsString:@"Dock"] || [name containsString:@"IconList"] || [name containsString:@"IconScroll"] || [name containsString:@"RootFolder"]) {
            UIView *blocked=nil;
            for (UIView *p=view;p;p=p.superview) if (p.hidden || p.alpha<0.01 || p.layer.hidden || p.layer.opacity<0.01) { blocked=p; break; }
            NFBDebugLog(@"home-return: %@ session=%lu class=%@ blocker=%@ frame=%@ layerOpacity=%.2f",phase,(unsigned long)identifier,name,NSStringFromClass(blocked.class),NSStringFromCGRect(view.frame),view.layer.opacity);
            logged++;
        }
        for (UIView *child in view.subviews) { if (queue.count>=128) break; [queue addObject:child]; }
    }
}
- (void)restore {
    if (self.restoring) return;
    BOOL timing=NFBDebugLoggingEnabled();
    CFAbsoluteTime restoreStart=timing ? CFAbsoluteTimeGetCurrent() : 0;
    if (timing) NFBLogHomeReturn(@"before",self.identifier,self.desktop);
    [NFBMovieHostLease() releaseSession:self.identifier];
    self.restoring=YES;
    self.mutationPhase=NFBDesktopMutationRestoring;
    self.widgetRefreshCancelled=YES;
    if (NFBDebugLoggingEnabled()) {
        NFBDebugLog(@"desktop-widget: restore begin startedHome=%d appearanceOwner=system parent=%@ original=%@",
            self.startedHome, NSStringFromClass(self.desktop.superview.class),
            NSStringFromClass(self.originalParent.class));
        NSUInteger budget=32; NFBLogWidgetHosts(self.desktop,0,&budget);
    }
    [self.timer invalidate]; self.timer=nil;
    [self finishWidgetRefresh];
    [self restoreDesktopInteraction];
    // UIKit owns the native home controller; the pane borrowed only its view.
    [self restoreDesktopAppearance];
    UIView *view=self.desktop;
    if (self.mutated && view && self.originalParent) {
        NFBAttemptCleanup(@"desktop geometry", ^{
            view.transform=CGAffineTransformIdentity;
            view.bounds=self.originalBounds; view.center=self.originalCenter;
            view.autoresizingMask=self.originalAutoresizing;
            view.translatesAutoresizingMaskIntoConstraints=self.originalTranslates;
            view.hidden=self.originalHidden; view.alpha=self.originalAlpha;
            view.userInteractionEnabled=self.originalInteraction;
        });
        NFBAttemptCleanup(@"desktop parent", ^{
            [self.originalParent insertSubview:view atIndex:MIN(self.originalIndex,self.originalParent.subviews.count)];
            view.transform=self.originalTransform;
        });
        if (NFBDebugLoggingEnabled()) {
            NFBDebugLog(@"desktop-widget: restored parent=%@ hidden=%d alpha=%.2f windowHidden=%d",
                NSStringFromClass(view.superview.class), view.hidden, view.alpha, view.window.hidden);
            NSUInteger budget=32; NFBLogWidgetHosts(view,0,&budget);
            __weak UIView *restoredDesktop=view;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
                UIView *desktop=restoredDesktop;
                if (!desktop || (session && session.desktop==desktop)) return;
                NFBDebugLog(@"desktop-widget: post-restore home parent=%@ windowHidden=%d",
                    NSStringFromClass(desktop.superview.class), desktop.window.hidden);
                NSUInteger laterBudget=32; NFBLogWidgetHosts(desktop,0,&laterBudget);
            });
        }
        NFBAttemptCleanup(@"desktop constraints", ^{ [NSLayoutConstraint activateConstraints:self.constraints]; });
        NFBAttemptCleanup(@"desktop layout", ^{ [self.originalParent setNeedsLayout]; [self.originalParent layoutIfNeeded]; });
        // A failing private parent must not leave the desktop owned by a retiring panel.
        if ([view isDescendantOfView:self.panel])
            NFBAttemptCleanup(@"desktop fallback parent", ^{ [self.window addSubview:view]; });
    }
    [self.independentAnchor removeFromSuperview]; self.independentAnchor=nil;
    NFBAttemptCleanup(@"panel", ^{ [self.panel removeFromSuperview]; });
    NFBAttemptCleanup(@"backdrop", ^{ [self.backgroundFrost removeFromSuperview]; });
    [self.siblingState restore]; self.siblingState=nil;
    if (self.windowMutated) {
        NFBAttemptCleanup(@"window color", ^{ self.window.backgroundColor=self.originalWindowColor; self.window.opaque=self.originalWindowOpaque; });
        NFBAttemptCleanup(@"window level", ^{ self.window.windowLevel=self.originalWindowLevel; });
        NFBAttemptCleanup(@"window alpha", ^{ self.window.alpha=self.originalWindowAlpha; });
        NFBAttemptCleanup(@"window interaction", ^{ self.window.userInteractionEnabled=self.originalWindowInteraction; });
        NFBAttemptCleanup(@"window visibility", ^{ self.window.hidden=self.originalWindowHidden; });
        NFBAttemptCleanup(@"window focus", ^{
            if (self.window.isKeyWindow && self.previousKeyWindow && !self.previousKeyWindow.hidden)
                [self.previousKeyWindow makeKeyWindow];
        });
    }
    if (timing && self.desktop) {
        NSUInteger returnedSession=self.identifier;
        __weak UIView *returnedDesktop=self.desktop;
        NFBLogHomeReturn(@"after",returnedSession,self.desktop);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (!session) NFBLogHomeReturn(@"settled",returnedSession,returnedDesktop);
        });
    }
    self.backgroundFrost=nil; self.window=nil; self.desktop=nil; self.originalParent=nil;
    self.constraints=nil;
    self.mutationPhase=NFBDesktopMutationFinished;
    NFBInvalidateWindowState();
    if (timing) NFBDebugLog(@"desktop-cleanup-time: session=%lu totalMs=%.3f",(unsigned long)self.identifier,(CFAbsoluteTimeGetCurrent()-restoreStart)*1000);
}

@end
// Disposable visual layer: no session or window restoration in completion.
static UIView *desktopReturnCover;
static NSUInteger desktopReturnToken;
void NFBUpdateDesktopReturnTransition(BOOL allowed) {
    if (!NSThread.isMainThread || allowed) return;
    desktopReturnToken++;
    [desktopReturnCover.layer removeAllAnimations];
    [desktopReturnCover removeFromSuperview]; desktopReturnCover=nil;
}
void NFBCloseMovieDesktopWithTransition(NSUInteger identifier) {
    if (!NSThread.isMainThread || !session || session.identifier!=identifier || session.restoring) return;
    NFBUpdateDesktopReturnTransition(NO);
    NFBDesktopSession *closing=session;
    UIWindow *window=closing.window;
    UIView *picture=nil;
    CGRect start=CGRectZero;
    CGFloat radius=closing.panel.layer.cornerRadius;
    BOOL animate=NFBDesktopAnimationsEnabled() && !NFBDesktopLocked() &&
        NFBCurrentWindowState().home && !closing.pendingApp.length;
    if (animate) @try {
        start=[closing.panel convertRect:closing.panel.bounds toView:window];
        picture=[closing.panel snapshotViewAfterScreenUpdates:NO];
    } @catch (NSException *error) { NFBErrorLog(@"desktop-return: snapshot failed %@",error); }
    // State restoration never waits for the animation (including capture failure).
    NFBCloseDesktopSplit();
    if (!picture || window.hidden || !NFBCurrentWindowState().home) return;
    UIView *cover=[[UIView alloc] initWithFrame:window.bounds];
    cover.backgroundColor=UIColor.blackColor;
    cover.userInteractionEnabled=NO; cover.accessibilityElementsHidden=YES;
    UIView *clip=[[UIView alloc] initWithFrame:start];
    clip.clipsToBounds=YES; clip.layer.cornerRadius=radius;
    clip.layer.cornerCurve=kCACornerCurveContinuous;
    picture.frame=clip.bounds;
    picture.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    picture.userInteractionEnabled=NO;
    [clip addSubview:picture]; [cover addSubview:clip]; [window addSubview:cover];
    desktopReturnCover=cover;
    NSUInteger token=++desktopReturnToken;
    [UIView animateWithDuration:0.28 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseInOut
        animations:^{
            clip.frame=cover.bounds;
            clip.layer.cornerRadius=0;
        } completion:^(__unused BOOL finished) {
            // Only our disposable cover is retired. Never touch newer sessions.
            [cover removeFromSuperview];
            if (desktopReturnToken==token) desktopReturnCover=nil;
        }];
    NFBDebugLog(@"desktop-return: transition session=%lu duration=0.28",(unsigned long)identifier);
}

BOOL NFBDesktopSplitActive(void) { return session != nil && !session.restoring; }
void NFBCloseDesktopSplit(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NFBCloseDesktopSplit(); }); return; }
    NFBDesktopSession *closing = session;
    session = nil;
    @try { [closing restore]; }
    @catch (NSException *exception) { NFBErrorLog(@"desktop restore failed: %@", exception); }
}
void NFBUpdateDesktopSplit(BOOL allowed) {
    if (!NSThread.isMainThread) return;
    if (!allowed) NFBCloseDesktopSplit();
    else [session check];
}
#ifndef NFB_DESKTOP_SIM_TEST
static void (*originalLaunchIcon)(id, SEL, id, id);
static void NFBDesktopLaunchIcon(id object, SEL selector, id icon, id actions) {
    if (NFBLaunchAppFromDesktopIcon(icon)) return;
    originalLaunchIcon(object,selector,icon,actions);
}
static BOOL NFBInstallDesktopLaunchHook(void) {
    static BOOL installed;
    if (installed) return YES;
    Class cls = NSClassFromString(@"SBIconController");
    SEL selector = NSSelectorFromString(@"_launchFromIconView:withActions:");
    Method method = class_getInstanceMethod(cls,selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 4 || strcmp(signature.methodReturnType,"v") ||
        [signature getArgumentTypeAtIndex:2][0] != '@' || [signature getArgumentTypeAtIndex:3][0] != '@') return NO;
    MSHookMessageEx(cls,selector,(IMP)NFBDesktopLaunchIcon,(IMP *)&originalLaunchIcon);
    installed = YES;
    return YES;
}
#endif
BOOL NFBShowDesktopInSplit(UIView *anchor) {
    if (!NSThread.isMainThread) return NO;
    NFBUpdateDesktopReturnTransition(NO);
    lastFailure = nil; failurePending = NO;
    if (!anchor.window) return NFBDesktopFail(@"没有可用的分屏窗口");
    if (NFBDesktopLocked()) return NFBDesktopFail(@"锁屏时不能打开桌面分屏");
    if (session) { NFBCloseDesktopSplit(); return YES; }
    NFBDesktopSession *next = [NFBDesktopSession new];
    next.identifier=++desktopSequence;
    next.mutationPhase=NFBDesktopMutationPreparing;
    @try {
        UIView *desktop = NFBDesktopSource(anchor);
        if (!desktop) return NFBDesktopFail(@"没有找到已加载的系统桌面视图");
        if (NFBDebugLoggingEnabled()) NFBWidgetWatchSample("before-transfer");
        if (NFBDebugLoggingEnabled()) {
            NFBDebugLog(@"desktop-widget: before-transfer desktop=%p parent=%@ window=%p",
                desktop,NSStringFromClass(desktop.superview.class),desktop.window);
            NSUInteger budget=32; NFBLogWidgetHosts(desktop,0,&budget);
        }
        NFBWindowState *state = NFBCurrentWindowState();
        next.startedHome = state.home;
        next.desktop = desktop; next.originalParent = desktop.superview; next.anchor = anchor;
        next.originalIndex = [desktop.superview.subviews indexOfObjectIdenticalTo:desktop];
        next.originalBounds = desktop.bounds; next.originalCenter = desktop.center;
        next.originalTransform = desktop.transform; next.originalAutoresizing = desktop.autoresizingMask;
        next.originalTranslates = desktop.translatesAutoresizingMaskIntoConstraints;
        next.originalHidden = desktop.hidden; next.originalInteraction = desktop.userInteractionEnabled;
        next.originalAlpha = desktop.alpha; next.constraints = NFBDesktopExternalConstraints(desktop);
        UIWindow *window = desktop.window;
        if (!window) return NFBDesktopFail(@"原生桌面窗口尚未加载，请先返回主屏幕再打开");
#ifndef NFB_DESKTOP_SIM_TEST
        if (!NFBInstallDesktopHitHook(window)) return NFBDesktopFail(@"原生桌面窗口触摸接口不可用");
        if (!NFBInstallDesktopLaunchHook()) return NFBDesktopFail(@"桌面应用分屏启动接口不可用");
        NFBInstallDesktopFolderAnimationHook();
#endif
        next.window = window;
        next.originalWindowLevel = window.windowLevel;
        next.originalWindowAlpha = window.alpha;
        next.originalWindowHidden = window.hidden;
        next.originalWindowInteraction = window.userInteractionEnabled;
        next.originalWindowColor = window.backgroundColor;
        next.originalWindowOpaque = window.opaque;
        for (UIWindow *candidate in NFBDesktopWindows())
            if (candidate.isKeyWindow) { next.previousKeyWindow = candidate; break; }
        // No new UIWindow or scene; do not replace the native root controller.
        UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
        panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
        panel.layer.cornerRadius = 14.0;
        panel.layer.cornerCurve = kCACornerCurveContinuous;
        panel.clipsToBounds = YES;
        // Start hidden when the open animation is enabled, otherwise the fully
        // assembled pane is visible for a frame before the scale-in begins.
        BOOL animateOpen = NFBDesktopAnimationsEnabled();
        if (animateOpen) { panel.alpha = 0; panel.transform = CGAffineTransformMakeScale(0.94,0.94); }
        next.panel = panel; [window addSubview:panel];
        // Clear so the wallpaper - from the desktop subtree or borrowed below -
        // shows through instead of a flat system background.
        UIView *canvas = [UIView new]; canvas.backgroundColor = UIColor.clearColor;
        canvas.clipsToBounds = YES; next.canvas = canvas; [panel addSubview:canvas];
        UIView *desktopHost = [UIView new]; desktopHost.backgroundColor = UIColor.clearColor;
        next.desktopHost = desktopHost; [canvas addSubview:desktopHost];
        // Verify geometry before touching the desktop hierarchy.
        if (![next place]) { [next restore]; return NO; }
        NFBDesktopTestCheckpoint(1); // Prepared: desktop has not moved.
        if (next.startedHome) {
            UIVisualEffectView *frost = [[UIVisualEffectView alloc] initWithEffect:nil];
            frost.frame = [desktop convertRect:desktop.bounds toView:next.originalParent];
            frost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            frost.contentView.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.25];
            [next.originalParent insertSubview:frost atIndex:next.originalIndex];
            next.backgroundFrost = frost;
        }
        next.mutated = YES;
        [NSLayoutConstraint deactivateConstraints:next.constraints];
        desktop.translatesAutoresizingMaskIntoConstraints = YES; desktop.autoresizingMask = UIViewAutoresizingNone;
        [desktopHost addSubview:desktop];
        next.mutationPhase=NFBDesktopMutationTransferred;
        // Establish native geometry once. The periodic check must not overwrite
        // positions or transforms that SpringBoard owns during folder animation.
        desktop.transform = CGAffineTransformIdentity;
        desktop.bounds = next.originalBounds;
        desktop.center = CGPointMake(CGRectGetMidX(next.originalBounds),CGRectGetMidY(next.originalBounds));
        desktop.hidden = NO; desktop.alpha = 1; desktop.userInteractionEnabled = YES;
        NFBDesktopTestCheckpoint(2); // Transferred: rollback must return native tree.
        if (![next place]) { [next restore]; return NO; }
        // The pane keeps the desktop's icons, folders and widgets; only the
        // wallpaper is forced on screen, and supplied when the subtree has none.
        [next adoptDesktopAppearance];
        [next adoptDesktopInteraction];
        if (next.wallpaperCount == 0) [next installPaneBackdrop];
        session = next;
        next.windowMutated = YES;
        // Raising the native window must not raise its fullscreen siblings over
        // the app behind the pane. Save them so close restores the native tree.
        next.siblingState=[NFBStateLedger new];
        for (UIView *sibling in window.subviews) {
            if (sibling==panel) continue;
            BOOL hidden=sibling.hidden;
            [next.siblingState remember:sibling key:@"sibling visibility" restore:^{ sibling.hidden=hidden; }];
            sibling.hidden=YES;
        }
        window.backgroundColor=UIColor.clearColor; window.opaque=NO;
        next.hostedWindowLevel = MAX(anchor.window.windowLevel + 2, UIWindowLevelStatusBar + 1);
        window.windowLevel = next.hostedWindowLevel;
        window.alpha = 1; window.userInteractionEnabled = YES; window.hidden = NO;
        [window bringSubviewToFront:panel];
        [next activateDesktop];
        NFBDesktopTestCheckpoint(3); // Window/focus leased: restore every captured property.
        NFBDebugLog(@"desktop-widget: open startedHome=%d appearanceOwner=system corner=%.2f desktop=%@ bounds=%@",
            next.startedHome, panel.layer.cornerRadius,
            NSStringFromClass(desktop.class), NSStringFromCGRect(desktop.bounds));
        // Observational samples only: do not wake, page or rebuild widget hosts.
        if (NFBDebugLoggingEnabled()) for (NSNumber *delay in @[@0.2, @0.8, @1.5]) {
            __weak NFBDesktopSession *weakSample = next;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NFBDesktopSession *sample = weakSample;
                if (!sample || session != sample || sample.restoring) return;
                NSUInteger budget = 32;
                NFBLogWidgetHosts(sample.desktop, 0, &budget);
            });
        }
        if (!next.startedHome) {
            // Layout the borrowed view without impersonating a controller transition.
            [desktop setNeedsLayout]; [desktop layoutIfNeeded];
            __weak NFBDesktopSession *refreshSession=next;
            dispatch_async(dispatch_get_main_queue(), ^{
                NFBDesktopSession *active=refreshSession;
                if (active && session==active && !active.restoring) {
                    @try {
                        [active.desktop setNeedsLayout]; [active.desktop layoutIfNeeded];
                        NFBDebugLog(@"desktop widget layout completed for fullscreen background");
                    } @catch (NSException *error) { NFBErrorLog(@"desktop widget activation failed: %@",error); }
                }
            });
        }
        // Next turn allows the transplanted desktop to attach its pager. Covers
        // both startedHome paths without inventing controller lifecycle calls.
        __weak NFBDesktopSession *widgetSession=next;
        dispatch_async(dispatch_get_main_queue(), ^{
            NFBDesktopSession *active=widgetSession;
            if (active && session==active && !active.restoring) [active refreshWidgetPage];
        });
        next.timer = [NSTimer timerWithTimeInterval:0.1 target:next selector:@selector(check) userInfo:nil repeats:YES];
        // Keep the 100 ms safety/launch checks; let the run loop coalesce
        // wakeups by up to 10 ms without increasing polling frequency.
        next.timer.tolerance = 0.01;
        [NSRunLoop.mainRunLoop addTimer:next.timer forMode:NSRunLoopCommonModes];
        // effect must be committed before the animation: it is not animatable, and
        // assigning it inside the block made the blur appear in one frame.
        next.backgroundFrost.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        if (animateOpen) {
            [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
                panel.alpha = 1; panel.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
        // Commit only once transfer, interaction, window and timer setup all
        // succeeded. Checks cannot act on a half-constructed desktop session.
        next.mutationPhase=NFBDesktopMutationActive;
        NFBDebugLog(@"desktop native host: view=%@ window=%@ root=%@ sameScene=%d pane=%@",
            NSStringFromClass(desktop.class), NSStringFromClass(window.class),
            NSStringFromClass(window.rootViewController.class), desktop.window==window,
            NSStringFromCGRect(next.panelFrame));
        return YES;
    } @catch (NSException *exception) {
        NSArray<NSString *> *frames = exception.callStackSymbols ?: @[];
        NSUInteger keep = MIN(frames.count, (NSUInteger)8);
        NFBDesktopFail([NSString stringWithFormat:@"桌面承载异常：%@ %@ %@", exception.name,
            exception.reason ?: @"", [[frames subarrayWithRange:NSMakeRange(0, keep)] componentsJoinedByString:@" <- "]]);
        if (session == next) session = nil;
        [next restore];
        return NO;
    }
}

UIView *NFBDesktopIndependentAnchor(void) {
    return session && !session.restoring ? session.independentAnchor : nil;
}
BOOL NFBReplaceSplitWithDesktop(UIView *window) {
    if (!NSThread.isMainThread || !window.window) return NO;
    if (NFBDesktopSplitActive()) { NFBCloseDesktopSplit(); return YES; }
    return NFBReplaceMoviePaneWithDesktop(window, 0);
}
BOOL NFBReplaceMoviePaneWithDesktop(UIView *window, NSUInteger retainedSession) {
    return NFBReplaceMoviePaneWithAnchor(window,retainedSession,nil);
}
BOOL NFBReplaceMoviePaneWithAnchor(UIView *window, NSUInteger retainedSession, UIView *anchor) {
    if (!NSThread.isMainThread || !window.window) return NO;
    if (retainedSession ? (NFBDesktopSessionIdentifier()!=retainedSession || !NFBMovieDesktopParked())
                        : NFBDesktopSplitActive()) return NO;
    // Unlike the generic bridge, this verified instance method cannot close a
    // newly-current landscape window and explicitly preserves the process.
    SEL close = NSSelectorFromString(@"closeWindowWithoutTerminatingProcessWithoutAnimation");
    NSMethodSignature *sig = NFBSignature(window, close);
    if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(void))) {
        NFBDesktopFail(@"当前 Open 未提供保留后台的精确关闭接口，未替换桌面");
        return NO;
    }
    if (!retainedSession) {
        if (!NFBShowDesktopInSplit(anchor ?: window)) return NO;
        NFBDesktopSession *active=session;
        UIView *proxy=[[UIView alloc] initWithFrame:active.panelFrame];
        proxy.userInteractionEnabled=NO;
        [active.window addSubview:proxy];
        active.independentAnchor=proxy; active.anchor=proxy;
    }
    @try {
        NSInvocation *call=[NSInvocation invocationWithMethodSignature:sig];
        call.selector=close; [call invokeWithTarget:window];
        NFBInvalidateWindowState();
        NFBDebugLog(@"desktop: house replaced exact portrait window=%p; process preserved",window);
        return YES;
    } @catch (NSException *error) {
        NFBErrorLog(@"desktop: portrait close failed %@",error);
        if (!retainedSession) NFBCloseDesktopSplit();
        return NO;
    }
}
