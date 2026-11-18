// Included by the Open adapter; mini views are never expanded movie targets.
@interface NFBMiniPosition : NSObject
@property(nonatomic,weak) UIView *parent,*above;
@property(nonatomic) CGPoint original,applied;
@property(nonatomic) BOOL placed,yielded,reordered;
@end
@implementation NFBMiniPosition @end
static NSMapTable<UIView *,NFBMiniPosition *> *miniPositions;
static void NFBReleaseMini(UIView *v,NFBMiniPosition *r) {
    if (r.placed && !r.yielded && v.superview==r.parent && boolStateOf(v,@"miniWindowModeEnabled")==1 && boolStateOf(v,@"isTransitioningFromMiniMode")==0 && CGPointEqualToPoint(v.center,r.applied)) {
        v.center=r.original;
        if (r.reordered && v.superview.subviews.lastObject==v && r.above && r.above.superview==v.superview) [r.parent insertSubview:v belowSubview:r.above];
    }
}
static NSArray<UIView *> *NFBPlaceMovieMinis(BOOL enabled,NFBOpenWindowObservation *obs) {
    if (!miniPositions) miniPositions=[NSMapTable weakToStrongObjectsMapTable];
    NSArray *minis=enabled ? obs.miniWindows : nil;
    for (UIView *v in miniPositions.keyEnumerator.allObjects) if (!enabled || (obs.sceneAvailable && ![minis containsObject:v])) {
        NFBReleaseMini(v,[miniPositions objectForKey:v]); [miniPositions removeObjectForKey:v];
    }
    if (!minis.count || NFBKeyboardVisible()) return minis ?: @[];
    // Only top-half portrait minis opt in. Keep unrelated lower/cross-host windows native.
    NSMutableArray<UIView *> *row=[NSMutableArray array]; UIView *parent=nil;
    NSArray *sorted=[minis sortedArrayUsingComparator:^NSComparisonResult(UIView *a,UIView *b){return [appOfWindow(a) compare:appOfWindow(b)];}];
    for (UIView *v in sorted) {
        NFBMiniPosition *r=[miniPositions objectForKey:v];
        if (r.placed && (r.parent!=v.superview || !CGPointEqualToPoint(v.center,r.applied))) r.yielded=YES;
        if (r.yielded || v.layer.animationKeys.count || v.superview.layer.animationKeys.count) continue;
        CGPoint c=[v.superview convertPoint:v.center toView:v.window];
        if (!r.placed && c.y>=CGRectGetMidY(v.window.bounds)) continue;
        if (!parent) parent=v.superview;
        if (parent==v.superview) [row addObject:v];
    }
    if (!row.count || row.count>3) return minis;
    CGRect area=[parent convertRect:UIEdgeInsetsInsetRect(parent.window.bounds,parent.window.safeAreaInsets) fromView:parent.window];
    CGFloat total=(row.count-1)*4; for (UIView *v in row) total+=CGRectGetWidth(v.frame);
    if (!isfinite(total) || total+8>CGRectGetWidth(area) || CGRectGetWidth(area)>=CGRectGetHeight(area)) return minis;
    CGFloat x=CGRectGetMidX(area)-total/2;
    for (UIView *v in row) {
        CGRect f=v.frame; NFBMiniPosition *r=[miniPositions objectForKey:v];
        if (!r) {r=[NFBMiniPosition new];r.parent=parent;r.original=v.center;[miniPositions setObject:r forKey:v];}
        CGPoint target=CGPointMake(v.center.x+x-CGRectGetMinX(f),v.center.y+CGRectGetMinY(area)+4-CGRectGetMinY(f));
        if (!CGPointEqualToPoint(v.center,target)) v.center=target;
        r.applied=v.center;r.placed=YES;x+=CGRectGetWidth(f)+4;
        NSArray *siblings=parent.subviews; NSUInteger index=[siblings indexOfObjectIdenticalTo:v];
        for (UIView *upper in obs.landscapeWindows) if (upper.superview==parent && upper.layer.zPosition==v.layer.zPosition && [siblings indexOfObjectIdenticalTo:upper]>index) {
            if (!r.reordered && index+1<siblings.count) r.above=siblings[index+1];
            [parent bringSubviewToFront:v];r.reordered=YES;break;
        }
    }
    return minis;
}
