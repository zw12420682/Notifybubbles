#import "NFBHotspot.h"
#import "NFBHotspotPolicy.h"
#import "NFBHotspotAdapters.h"
#import "NFBDebugLog.h"
#import <substrate.h>
#include <dlfcn.h>
static BOOL configured;
static double idleSeconds=300;
static NSTimer *timer;
static NFBHotspotPolicy policy;
static id hotspotController;
static void *connectivityLibrary, *modemLibrary;
static void NFBCheckHotspot(void);
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
    @try { hotspotController=[[cls alloc] init]; } @catch (__unused NSException *error) {}
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
        if (NFBBooleanGetterCompatible(controller,NSSelectorFromString(name))) return NFBCheckedBool(controller,name,NO) ? 1 : 0;
    return -1;
}
static id NFBTelephony(void) {
    return NFBCheckedObject(NSClassFromString(@"SBTelephonyManager"),@"sharedTelephonyManager");
}
static void NFBReadHotspot(int *state, long long *clients) {
    id controller=NFBHotspotController();
    NFBHotspotVoid(controller,@"_updateState");
    *state=NFBControllerState(controller);
    if (*state < 0) *state=NFBMISState(NFBHotspotManager());
    *clients=-1;
    if (!NFBHotspotClientCount(NFBTelephony(),clients)) NFBHotspotClientCount(controller,clients);
}
static BOOL NFBDisableHotspot(void) {
    // Check again immediately before changing anything; unknown is never zero.
    int state=-1; long long clients=-1; NFBReadHotspot(&state,&clients);
    if (state != 1 || clients != 0) return NO;
    id controller=NFBHotspotController();
    // Prefer an explicit one-way discoverability setter when available.
    for (NSString *name in @[@"setDiscoverable:",@"_setDiscoverable:"]) {
        SEL selector=NSSelectorFromString(name); NSMethodSignature *sig=NFBSignature(controller,selector);
        if (!sig || sig.numberOfArguments != 3 || strcmp(NFBHotspotType(sig.methodReturnType),"v")) continue;
        const char *type=NFBHotspotType([sig getArgumentTypeAtIndex:2]);
        if (strcmp(type,"B") && strcmp(type,"c")) continue;
        @try { ((void (*)(id,SEL,BOOL))objc_msgSend)(controller,selector,NO); return YES; }
        @catch (__unused NSException *error) { return NO; }
    }
    // Control Center's native toggle is used only after a fresh, known ON read
    // in this same main-queue turn, matching the system hotspot switch path.
    if (NFBControllerState(controller) == 1 && NFBHotspotVoid(controller,@"_toggleState")) return YES;
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
    if (NFBHotspotShouldClose(&policy,configured,state,clients,NSProcessInfo.processInfo.systemUptime,idleSeconds)) {
        if (NFBDisableHotspot()) {
            policy.submitted=true;
            NFBDebugLog(@"hotspot auto-close submitted after %.0f seconds without clients",idleSeconds);
        } else NFBHotspotReset(&policy);
    }
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
    [timer invalidate]; timer=nil;
    if (!enabled) return;
    NFBInstallHotspotObservers();
    timer=[NSTimer timerWithTimeInterval:5 repeats:YES block:^(__unused NSTimer *tick) { NFBCheckHotspot(); }];
    timer.tolerance=1;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    NFBCheckHotspot();
}
