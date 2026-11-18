// Included by the Open adapter; mini views are never expanded movie targets.
@interface NFBMiniPosition : NSObject
@property(nonatomic,weak) UIView *parent,*above;
@property(nonatomic) CGPoint original,applied;
@property(nonatomic) BOOL placed,yielded,reordered,reserved;
@property(nonatomic) CGFloat order;
@end
@implementation NFBMiniPosition @end
static NSMapTable<UIView *,NFBMiniPosition *> *miniPositions;
static __weak UIView *nfbPickedMini,*nfbOldLower,*nfbSwapParent;
static CGPoint nfbVacantEdge; static CGFloat nfbVacantOrder; static CFTimeInterval nfbSwapUntil; static BOOL nfbMiniIssued;
static void NFBCancelMiniSwap(void) { nfbPickedMini=nil;nfbOldLower=nil;nfbSwapParent=nil;nfbMiniIssued=NO; }
#ifndef NFB_DESKTOP_SIM_TEST
#import <substrate.h>
static void (*nfbOriginalMiniTap)(UIView *,SEL,UIGestureRecognizer *);
static void NFBOnMiniTap(UIView *v,SEL cmd,UIGestureRecognizer *g) {
    if (NSThread.isMainThread && g.state==UIGestureRecognizerStateEnded) {
        NFBCancelMiniSwap(); NFBMiniPosition *r=[miniPositions objectForKey:v];
        if (movieWasEnabled && r.placed && !r.yielded && r.parent==v.superview && boolStateOf(v,@"miniWindowModeEnabled")==1 && !NFBKeyboardVisible()) {
            UIView *lower=attachmentWindow();
            if (lower && lower!=v && lower.superview==r.parent && !movieLandscape(lower) && !NFBDesktopSplitActive()) {
                nfbPickedMini=v;nfbOldLower=lower;nfbSwapParent=r.parent;nfbVacantOrder=r.order;nfbVacantEdge=CGPointMake(CGRectGetMaxX(v.frame),CGRectGetMaxY(v.frame));nfbSwapUntil=CACurrentMediaTime()+1.6;
            }
        }
    }
    nfbOriginalMiniTap(v,cmd,g);
}
static void NFBArmMiniTap(UIView *v) {
    if (!v || nfbOriginalMiniTap) return;
    Class cls=NFBTrollFloatingWindowClass(); SEL sel=NSSelectorFromString(@"handleMiniModeOverlayTap:"); NSMethodSignature *sig=NFBSignature(v,sel);
    if (cls && sig.numberOfArguments==3 && !strcmp(sig.methodReturnType,@encode(void)) && [sig getArgumentTypeAtIndex:2][0]=='@') MSHookMessageEx(cls,sel,(IMP)NFBOnMiniTap,(IMP *)&nfbOriginalMiniTap);
}
#endif
static void NFBFinishMiniSwap(BOOL enabled,NFBOpenWindowObservation *obs) {
    UIView *b=nfbPickedMini,*d=nfbOldLower,*p=nfbSwapParent;
    if (!enabled || !b || !d || !p || b.superview!=p || d.superview!=p || !visibleView(b) || !visibleView(d) || NFBKeyboardVisible() || CACurrentMediaTime()>nfbSwapUntil || NFBDesktopSplitActive()) { NFBCancelMiniSwap();return; }
    if (obs.portrait!=b || boolStateOf(b,@"miniWindowModeEnabled")!=0 || boolStateOf(b,@"isTransitioningFromMiniMode")!=0) return;
    if (movieLandscape(d) || boolStateOf(d,@"isClosingWithKeepAliveAnimation")!=0) { NFBCancelMiniSwap();return; }
    if ([obs.miniWindows containsObject:d]) {
        NFBMiniPosition *r=[miniPositions objectForKey:d] ?: [NFBMiniPosition new]; r.parent=p;r.original=d.center;r.order=nfbVacantOrder;r.reserved=YES;[miniPositions setObject:r forKey:d]; NFBCancelMiniSwap();return;
    }
    if (!nfbMiniIssued && [obs.windows containsObject:d] && boolStateOf(d,@"miniWindowModeEnabled")==0 && boolStateOf(d,@"isTransitioningFromMiniMode")==0) {
        SEL sel=NSSelectorFromString(@"setMiniWindowModeEnabled:animated:");NSMethodSignature *sig=NFBSignature(d,sel);nfbMiniIssued=YES;
        SEL scale=NSSelectorFromString(@"clampedVisualScale"), motion=NSSelectorFromString(@"runMiniModeMatchedTransitionFromVisualScale:toVisualScale:startCenter:targetCenter:");
        NSMethodSignature *ss=NFBSignature(d,scale), *ms=NFBSignature(d,motion);
        if (sig.numberOfArguments!=4 || strcmp(sig.methodReturnType,@encode(void)) || strcmp([sig getArgumentTypeAtIndex:2],@encode(BOOL)) || strcmp([sig getArgumentTypeAtIndex:3],@encode(BOOL)) || ss.numberOfArguments!=2 || strcmp(ss.methodReturnType,@encode(CGFloat)) || ms.numberOfArguments!=6 || strcmp(ms.methodReturnType,@encode(void)) || strcmp([ms getArgumentTypeAtIndex:2],@encode(CGFloat)) || strcmp([ms getArgumentTypeAtIndex:3],@encode(CGFloat)) || strcmp([ms getArgumentTypeAtIndex:4],@encode(CGPoint)) || strcmp([ms getArgumentTypeAtIndex:5],@encode(CGPoint))) return;
        CGPoint start=d.center; CGFloat from=((CGFloat (*)(id,SEL))objc_msgSend)(d,scale);
        if (!(from>0) || !isfinite(from)) return;
        ((void (*)(id,SEL,BOOL,BOOL))objc_msgSend)(d,sel,YES,NO);
        if (d.superview!=p || boolStateOf(d,@"miniWindowModeEnabled")!=1) return;
        CGFloat to=((CGFloat (*)(id,SEL))objc_msgSend)(d,scale); CGRect f=d.frame;
        CGPoint end=CGPointMake(d.center.x+nfbVacantEdge.x-CGRectGetMaxX(f),d.center.y+nfbVacantEdge.y-CGRectGetMaxY(f));
        if (!(to>0) || !isfinite(to) || !isfinite(end.x) || !isfinite(end.y)) return;
        ((void (*)(id,SEL,CGFloat,CGFloat,CGPoint,CGPoint))objc_msgSend)(d,motion,from,to,start,end);
    }
}

static void NFBReleaseMini(UIView *v,NFBMiniPosition *r) {
    if (r.placed && !r.yielded && v.superview==r.parent && boolStateOf(v,@"miniWindowModeEnabled")==1 && boolStateOf(v,@"isTransitioningFromMiniMode")==0 && CGPointEqualToPoint(v.center,r.applied)) {
        v.center=r.original;
        if (r.reordered && v.superview.subviews.lastObject==v && r.above && r.above.superview==v.superview) [r.parent insertSubview:v belowSubview:r.above];
    }
}
static NSArray<UIView *> *NFBPlaceMovieMinis(BOOL enabled,NFBOpenWindowObservation *obs) {
    if (!miniPositions) miniPositions=[NSMapTable weakToStrongObjectsMapTable];
    NSArray *minis=enabled ? obs.miniWindows : nil;
    NFBFinishMiniSwap(enabled,obs);
#ifndef NFB_DESKTOP_SIM_TEST
    NFBArmMiniTap(minis.firstObject);
#endif
    for (UIView *v in miniPositions.keyEnumerator.allObjects) if (!enabled || (obs.sceneAvailable && ![minis containsObject:v])) {
        NFBReleaseMini(v,[miniPositions objectForKey:v]); [miniPositions removeObjectForKey:v];
    }
    if (enabled && nfbPickedMini && nfbOldLower) return minis ?: @[]; // reserve row during exchange
    if (!minis.count || NFBKeyboardVisible()) return minis ?: @[];
    // Only top-half portrait minis opt in. Keep unrelated lower/cross-host windows native.
    NSMutableArray<UIView *> *row=[NSMutableArray array]; UIView *parent=nil;
    NSArray *sorted=[minis sortedArrayUsingComparator:^NSComparisonResult(UIView *a,UIView *b){return [appOfWindow(a) compare:appOfWindow(b)];}];
    for (UIView *v in sorted) {
        NFBMiniPosition *r=[miniPositions objectForKey:v];
        if ((r.reserved || r.placed) && (v.layer.animationKeys.count || v.superview.layer.animationKeys.count)) return minis;
        if (r.placed && (r.parent!=v.superview || !CGPointEqualToPoint(v.center,r.applied))) r.yielded=YES;
        if (r.yielded || v.layer.animationKeys.count || v.superview.layer.animationKeys.count) continue;
        CGPoint c=[v.superview convertPoint:v.center toView:v.window];
        if (!r.placed && !r.reserved && c.y>=CGRectGetMidY(v.window.bounds)) continue;
        if (!parent) parent=v.superview;
        if (parent==v.superview) [row addObject:v];
    }
    if (!row.count || row.count>3) return minis;
    CGRect area=[parent convertRect:UIEdgeInsetsInsetRect(parent.window.bounds,parent.window.safeAreaInsets) fromView:parent.window];
    UIView *base=obs.landscapeWindows.count==1 ? obs.landscapeWindows.firstObject : nil;
    UIView *lower=obs.portrait ?: (NFBDesktopIndependentAnchor() ?: movieDesktopAnchor);
    CGFloat bottom=NAN;
    if (base.window && base.window.windowScene==parent.window.windowScene) bottom=CGRectGetMaxY([base convertRect:base.bounds toView:parent]);
    else if (lower.window && lower.window.windowScene==parent.window.windowScene) bottom=CGRectGetMinY([lower convertRect:lower.bounds toView:parent])-4;
    if (!isfinite(bottom) || bottom>CGRectGetMaxY(area) || bottom<=CGRectGetMinY(parent.bounds)) return minis;
    CGFloat nextOrder=0; for (UIView *v in row) { NFBMiniPosition *r=[miniPositions objectForKey:v]; if (r) nextOrder=MAX(nextOrder,r.order+1); }
    for (UIView *v in row) { if (![miniPositions objectForKey:v]) { NFBMiniPosition *r=[NFBMiniPosition new];r.order=nextOrder++;r.parent=parent;r.original=v.center;[miniPositions setObject:r forKey:v]; } }
    [row sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){CGFloat x=[miniPositions objectForKey:a].order,y=[miniPositions objectForKey:b].order;return x<y?NSOrderedAscending:(x>y?NSOrderedDescending:NSOrderedSame);}];
    CGFloat total=(row.count-1)*2; for (UIView *v in row) { if (bottom-CGRectGetHeight(v.frame)<CGRectGetMinY(parent.bounds)) return minis; total+=CGRectGetWidth(v.frame); }
    if (!isfinite(total) || total+8>CGRectGetWidth(area) || CGRectGetWidth(area)>=CGRectGetHeight(area)) return minis;
    CGFloat x=CGRectGetMaxX(area)-4;
    for (UIView *v in row) {
        CGRect f=v.frame; NFBMiniPosition *r=[miniPositions objectForKey:v];
        if (!r) {r=[NFBMiniPosition new];r.parent=parent;r.original=v.center;[miniPositions setObject:r forKey:v];}
        CGPoint target=CGPointMake(v.center.x+x-CGRectGetMaxX(f),v.center.y+bottom-CGRectGetMaxY(f));
        if (!CGPointEqualToPoint(v.center,target)) {
            if (r.reserved && !UIAccessibilityIsReduceMotionEnabled()) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{ v.center=target; } completion:nil];
            else v.center=target;
        }
        r.reserved=NO;
        r.applied=v.center;r.placed=YES;x-=CGRectGetWidth(f)+2;
        NSArray *siblings=parent.subviews; NSUInteger index=[siblings indexOfObjectIdenticalTo:v];
        for (UIView *upper in obs.landscapeWindows) if (upper.superview==parent && upper.layer.zPosition==v.layer.zPosition && [siblings indexOfObjectIdenticalTo:upper]>index) {
            if (!r.reordered && index+1<siblings.count) r.above=siblings[index+1];
            [parent bringSubviewToFront:v];r.reordered=YES;break;
        }
    }
    return minis;
}
