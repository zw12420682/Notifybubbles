#import "NFBHotspot.h"
#import "NFBHotspotPolicy.h"
#import "NFBHotspotAdapters.h"
#import "NFBDebugLog.h"
#import <substrate.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
static BOOL configured;
static double idleSeconds=300;
static NSTimer *timer;
static NFBHotspotPolicy policy;
static id hotspotController;
static void *connectivityLibrary, *modemLibrary;
static void NFBCheckHotspot(void);
static double submittedAt;
static unsigned closeAttempts;
static BOOL nativeToggleUsed;
static id NFBHotspotManager(void) {
    if (!NSClassFromString(@"MISManager") && !modemLibrary)
        modemLibrary=dlopen("/System/Library/PreferenceBundles/WirelessModemSettings.bundle/WirelessModemSettings",RTLD_LAZY);
    return NFBCheckedObject(NSClassFromString(@"MISManager"),@"sharedManager");
}
static id NFBHotspotController(void) {
    if (hotspotController) return hotspotController;
    if (!NSClassFromString(@"CCUIConnectivityHotspotViewController") && !connectivityLibrary)
        connectivityLibrary=dlopen("/System/Library/ControlCenter/Bundles/ConnectivityModule.bundle/ConnectivityModule",RTLD_LAZY);
    Class cls=NSClassFromString(@"CCUIConnectivityHotspotViewController");
    if (!cls) return nil;
    @try { hotspotController=[[cls alloc] init];
        if ([hotspotController isKindOfClass:UIViewController.class]) [(UIViewController *)hotspotController loadViewIfNeeded];
    } @catch (__unused NSException *error) {}
    return hotspotController;
}
static BOOL NFBHotspotVoid(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name); NSMethodSignature *sig=NFBSignature(object,selector);
    if (!sig || sig.numberOfArguments != 2 || strcmp(NFBHotspotType(sig.methodReturnType),"v")) return NO;
    @try { ((void (*)(id,SEL))objc_msgSend)(object,selector); return YES; }
    @catch (__unused NSException *error) { return NO; }
}
static int NFBControllerState(id controller) {
    for (NSString *name in @[@"discoverable",@"isDiscoverable"])
        if (NFBBooleanGetterCompatible(controller,NSSelectorFromString(name))) {
            @try { return ((BOOL (*)(id,SEL))objc_msgSend)(controller,NSSelectorFromString(name)) ? 1 : 0; }
            @catch (__unused NSException *error) { return -1; }
        }
    return -1;
}
static id NFBTelephony(void) {
    Class cls=NSClassFromString(@"SBTelephonyManager");
    for (NSString *selector in @[@"sharedTelephonyManager",@"sharedInstance"]) {
        id object=NFBCheckedObject(cls,selector);
        if (object && [object isKindOfClass:cls]) return object;
    }
    return nil;
}
static void NFBReadHotspot(int *state, long long *clients) {
    id controller=NFBHotspotController();
    NFBHotspotVoid(controller,@"_updateState");
    int controlState=NFBControllerState(controller), modemState=NFBMISState(NFBHotspotManager());
    // Discoverability is the user's hotspot switch; modem service can be OFF
    // while that switch remains enabled with no connected clients.
    *state=NFBHotspotResolvedState(controlState,modemState);
    *clients=-1;
    if (!NFBHotspotClientCount(NFBTelephony(),clients) && !NFBHotspotClientCount(controller,clients))
        NFBHotspotClientCount(NFBHotspotManager(),clients);
}
static BOOL NFBDisableHotspot(void) {
    // Check again immediately before changing anything; unknown is never zero.
    int state=-1; long long clients=-1; NFBReadHotspot(&state,&clients);
    if (state != 1 || clients != 0) return NO;
    id controller=NFBHotspotController();
    // Use the native Control Center action, not its discoverable property setter:
    // updating a UI property alone does not necessarily disable the service.
    // A tracking session may toggle at most once; retries are one-way MIS OFF.
    if (!nativeToggleUsed && NFBControllerState(controller) == 1 && NFBHotspotVoid(controller,@"_toggleState")) {
        nativeToggleUsed=YES;
        return YES;
    }
    return NFBMISSetOff(NFBHotspotManager());
}
static void NFBCheckHotspot(void) {
    if (!NSThread.isMainThread || !configured) return;
    int state=-1; long long clients=-1; NFBReadHotspot(&state,&clients);
    static BOOL reportedUnavailable;
    if (state < 0 || clients < 0) {
        if (!reportedUnavailable) {
            reportedUnavailable=YES;
            NFBErrorLog(@"hotspot auto-close paused: state=%d clients=%lld (unknown is not idle)",state,clients);
            NFBDumpMethods(NFBTelephony(),NO,@"hotspot telemetry",@[@"tether",@"hotspot",@"modem"]);
        }
    } else reportedUnavailable=NO;
    double now=NSProcessInfo.processInfo.systemUptime;
    if (policy.submitted && state == 0) NFBErrorLog(@"hotspot auto-close confirmed OFF");
    BOOL eligible=configured && state == 1 && clients == 0;
    if (!eligible) { closeAttempts=0; nativeToggleUsed=NO; submittedAt=0; }
    if (policy.submitted && eligible && now-submittedAt >= 10 && closeAttempts < 3) {
        policy.submitted=false;
        NFBErrorLog(@"hotspot remains ON after close request; retrying explicit OFF");
    }
    BOOL wasTracking=policy.tracking;
    if (NFBHotspotShouldClose(&policy,configured,state,clients,now,idleSeconds)) {
        closeAttempts++; submittedAt=now; policy.submitted=true;
        BOOL sent=NFBDisableHotspot();
        NFBErrorLog(@"hotspot auto-close attempt %u: submitted=%d; verifying actual switch",closeAttempts,sent);
    }
    if (!wasTracking && policy.tracking) NFBErrorLog(@"hotspot idle timer started: %.0f seconds, clients=0",idleSeconds);

}
static void NFBHotspotChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{ NFBCheckHotspot(); });
}
static void (*originalModemChanged)(id,SEL);
static void (*originalStoreChanged)(id,SEL);
static void NFBTelemetryChanged(id object) {
    long long clients=-1;
    BOOL connected=NFBHotspotClientCount(object,&clients) && clients > 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!configured) return;
        if (connected) NFBHotspotReset(&policy);
        NFBCheckHotspot();
    });
}
static void NFBModemChanged(id object,SEL selector) { originalModemChanged(object,selector); NFBTelemetryChanged(object); }
static void NFBStoreChanged(id object,SEL selector) { originalStoreChanged(object,selector); NFBTelemetryChanged(object); }
static void NFBInstallHotspotObservers(void) {
    static BOOL installed;
    if (installed) return;
    installed=YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),NULL,NFBHotspotChanged,CFSTR("SBNetworkTetheringStateChangedNotification"),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    Class cls=NSClassFromString(@"SBTelephonyManager");
    NSArray *names=@[@"noteWirelessModemChanged",@"_queue_noteWirelessModemDynamicStoreChanged"];
    for (NSUInteger index=0;index<names.count;index++) {
        SEL selector=NSSelectorFromString(names[index]); Method method=class_getInstanceMethod(cls,selector);
        if (!method) continue;
        NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType,"v")) continue;
        if (index==0) MSHookMessageEx(cls,selector,(IMP)NFBModemChanged,(IMP *)&originalModemChanged);
        else MSHookMessageEx(cls,selector,(IMP)NFBStoreChanged,(IMP *)&originalStoreChanged);
    }
}
void NFBConfigureHotspotAutoClose(BOOL enabled,double minutes) {
    if (!NSThread.isMainThread) return;
    configured=enabled;
    idleSeconds=(isfinite(minutes) ? MIN(60,MAX(1,minutes)) : 5)*60;
    NFBHotspotReset(&policy);
    closeAttempts=0; nativeToggleUsed=NO; submittedAt=0;
    NFBErrorLog(@"hotspot auto-close configured: enabled=%d timeout=%.0f",enabled,idleSeconds);
    [timer invalidate]; timer=nil;
    if (!enabled) return;
    NFBInstallHotspotObservers();
    timer=[NSTimer timerWithTimeInterval:5 repeats:YES block:^(__unused NSTimer *tick) { NFBCheckHotspot(); }];
    timer.tolerance=1;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    NFBCheckHotspot();
}
