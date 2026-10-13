#pragma once
#import "NFBInterfaces.h"
#include <stdint.h>
#include <limits.h>
static inline const char *NFBHotspotType(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV",*type)) ++type;
    return type;
}
static inline BOOL NFBHotspotClientCount(id object, long long *count) {
    if (!object || !count || object_isClass(object)) return NO;
    @try {
        for (NSString *name in @[@"numberOfNetworkTetheredDevices", @"numberOfConnectedDevices"]) {
            SEL selector=NSSelectorFromString(name);
            NSMethodSignature *sig=NFBSignature(object,selector);
            if (!sig || sig.numberOfArguments != 2) continue;
            long long value=-1; const char *type=NFBHotspotType(sig.methodReturnType);
            if (!strcmp(type,"i")) value=((int (*)(id,SEL))objc_msgSend)(object,selector);
            else if (!strcmp(type,"I")) value=((unsigned int (*)(id,SEL))objc_msgSend)(object,selector);
            else if (!strcmp(type,"q")) value=((long long (*)(id,SEL))objc_msgSend)(object,selector);
            else if (!strcmp(type,"Q")) {
                unsigned long long raw=((unsigned long long (*)(id,SEL))objc_msgSend)(object,selector);
                if (raw <= 1024) value=(long long)raw;
            }
            if (value >= 0 && value <= 1024) { *count=value; return YES; }
        }
        // Legacy SpringBoard stores the total tethering client count here.
        // Read only a validated four-byte integer inside the actual instance.
        Class cls=object_getClass(object);
        Ivar field=class_getInstanceVariable(cls,"_numberOfNetworkTetheredDevices");
        if (!field) return NO;
        const char *type=NFBHotspotType(ivar_getTypeEncoding(field));
        ptrdiff_t offset=ivar_getOffset(field); size_t size=class_getInstanceSize(cls);
        if ((strcmp(type,"i") && strcmp(type,"I")) || offset < (ptrdiff_t)sizeof(void *) || size < sizeof(int) || (size_t)offset > size-sizeof(int)) return NO;
        int value=-1; memcpy(&value,(const uint8_t *)(__bridge const void *)object+offset,sizeof(value));
        if (value < 0 || value > 1024) return NO;
        *count=value; return YES;
    } @catch (__unused NSException *error) { return NO; }
}
static inline int NFBMISState(id manager) {
    @try {
        SEL selector=NSSelectorFromString(@"getState:andReason:");
        NSMethodSignature *sig=NFBSignature(manager,selector);
        if (!sig || sig.numberOfArguments != 4 || strcmp(NFBHotspotType(sig.methodReturnType),"v")) return -1;
        const char *stateType=NFBHotspotType([sig getArgumentTypeAtIndex:2]);
        const char *reasonType=NFBHotspotType([sig getArgumentTypeAtIndex:3]);
        if ((strcmp(stateType,"^i") && strcmp(stateType,"^I")) || strcmp(reasonType,"^i")) return -1;
        int state=0,reason=0;
        ((void (*)(id,SEL,int *,int *))objc_msgSend)(manager,selector,&state,&reason);
        return state == 1023 ? 1 : (state == 1022 ? 0 : -1);
    } @catch (__unused NSException *error) { return -1; }
}
static inline BOOL NFBMISSetOff(id manager) {
    @try {
        SEL selector=NSSelectorFromString(@"setState:"); NSMethodSignature *sig=NFBSignature(manager,selector);
        if (!sig || sig.numberOfArguments != 3 || strcmp(NFBHotspotType(sig.methodReturnType),"v")) return NO;
        const char *type=NFBHotspotType([sig getArgumentTypeAtIndex:2]);
        if (strcmp(type,"i") && strcmp(type,"I")) return NO;
        ((void (*)(id,SEL,int))objc_msgSend)(manager,selector,1022);
        return YES;
    } @catch (__unused NSException *error) { return NO; }
}
