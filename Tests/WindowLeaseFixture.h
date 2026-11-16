#import "NFBWindowLease.h"
static void RunWindowLeaseTests(void) {
    NFBWindowLease *lease=[NFBWindowLease new];
    UIWindow *desktop=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,390,844)];
    desktop.windowLevel=1001;
    UIWindow *a=[[UIWindow alloc] initWithFrame:desktop.bounds];a.hidden=NO;a.windowLevel=30;
    UIWindow *b=[[UIWindow alloc] initWithFrame:desktop.bounds];b.hidden=NO;b.windowLevel=40;
    [lease updateHosts:@[a] desktop:desktop session:1];
    Check(a.windowLevel==1002 && [lease ownsHost:a session:1],@"level and touch acquired together");
    [lease updateHosts:@[b] desktop:desktop session:2];
    Check(a.windowLevel==30 && b.windowLevel==1002,@"new desktop session releases previous host");
    [lease releaseSession:1];
    Check(b.windowLevel==1002 && [lease ownsHost:b session:2],@"old teardown cannot release new touch lease");
    b.windowLevel=2002; // ARC/other owner takes over; do not contest it.
    Check(![lease ownsHost:b session:2],@"external mutation disables hit override immediately");
    [lease updateHosts:@[b] desktop:desktop session:2];
    Check(b.windowLevel==2002,@"layout does not fight external window level");
    [lease releaseSession:2];
    Check(b.windowLevel==2002,@"release does not restore over external owner");
    b.windowLevel=40;
    [lease updateHosts:@[b] desktop:desktop session:3];
    b.hidden=YES;
    [lease updateHosts:@[b] desktop:desktop session:3];
    Check(b.windowLevel==40 && ![lease ownsHost:b session:3],@"hidden host releases level and touch");
    b.hidden=NO;
    [lease updateHosts:@[a,b] desktop:desktop session:3];
    [lease updateHosts:@[a] desktop:desktop session:3];
    Check(b.windowLevel==40 && a.windowLevel==1002,@"host-set replacement restores removed host");
    UIView *root=[[UIView alloc] initWithFrame:CGRectMake(20,20,120,80)];
    UIView *control=[[UIView alloc] initWithFrame:root.bounds]; [root addSubview:control]; [a addSubview:root];
    UIView *unrelated=[[UIView alloc] initWithFrame:a.bounds]; [a addSubview:unrelated];
    [lease publishTouchWindows:@[root] session:3];
    Check([lease nativeHitInHost:a point:CGPointMake(30,30) event:nil session:3]==control,
        @"captured floating root reaches its native controls, unrelated overlay excluded");
    Check([lease nativeHitInHost:a point:CGPointMake(200,200) event:nil session:3]==nil,
        @"movie host empty space passes through to desktop");
    [lease publishTouchWindows:@[] session:2];
    Check([lease nativeHitInHost:a point:CGPointMake(30,30) event:nil session:3]==control,
        @"stale publication cannot replace new session roots");
    root.hidden=YES;
    Check([lease nativeHitInHost:a point:CGPointMake(30,30) event:nil session:3]==nil,@"hidden root no longer accepts touches");
    root.hidden=NO; [root removeFromSuperview];
    Check([lease nativeHitInHost:a point:CGPointMake(30,30) event:nil session:3]==nil,@"detached root cannot route stale touches");
    [lease releaseSession:3];
    Check(a.windowLevel==30,@"final teardown restores original host");
    a.hidden=YES;b.hidden=YES;
}
