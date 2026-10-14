#pragma once
#import "NFBInterfaces.h"
#include <stdint.h>
#include <limits.h>
static inline const char *NFBHotspotType(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV",*type)) ++type;
    return type;
}
static inline int NFBHotspotResolvedState(int control, int modem) {
    if (control == 1 || modem == 1) return 1;
    if (control == 0 || modem == 0) return 0;
    return -1;
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
            else if (!strcmp(type,"@")) {
                id number=((id (*)(id,SEL))objc_msgSend)(object,selector);
                if ([number isKindOfClass:NSNumber.class]) {
                    const char *numberType=[(NSNumber *)number objCType];
                    if (!strcmp(numberType,"i") || !strcmp(numberType,"I") || !strcmp(numberType,"q") || !strcmp(numberType,"Q"))
                        value=[(NSNumber *)number longLongValue];
                }
            }
            if (value >= 0 && value <= 1024) { *count=value; return YES; }
        }
        // Legacy SpringBoard stores the total tethering client count here.
        // Read only the validated integer width inside the actual instance.
        Class cls=object_getClass(object);
        Ivar field=class_getInstanceVariable(cls,"_numberOfNetworkTetheredDevices");
        if (!field) return NO;
        const char *type=NFBHotspotType(ivar_getTypeEncoding(field));
        size_t width = (!strcmp(type,"i") || !strcmp(type,"I")) ? 4 :
            ((!strcmp(type,"q") || !strcmp(type,"Q")) ? 8 : 0);
        ptrdiff_t offset=ivar_getOffset(field); size_t size=class_getInstanceSize(cls);
        if (!width || offset < (ptrdiff_t)sizeof(void *) || size < width || (size_t)offset > size-width) return NO;
        uint64_t value=0; memcpy(&value,(const uint8_t *)(__bridge const void *)object+offset,width);
        if (value > 1024) return NO;
        *count=(long long)value; return YES;
    } @catch (__unused NSException *error) { return NO; }
}
static inline int NFBMISState(id manager) {
    @try {
        SEL selector=NSSelectorFromString(@"getState:andReason:");
        NSMethodSignature *sig=NFBSignature(manager,selector);
        if (!sig || sig.numberOfArguments != 4 || strcmp(NFBHotspotType(sig.methodReturnType),"v")) return -1;
        const char *stateType=NFBHotspotType([sig getArgumentTypeAtIndex:2]);
        const char *reasonType=NFBHotspotType([sig getArgumentTypeAtIndex:3]);
        BOOL wideState=!strcmp(stateType,"^q") || !strcmp(stateType,"^Q");
        BOOL wideReason=!strcmp(reasonType,"^q") || !strcmp(reasonType,"^Q");
        if ((!wideState && strcmp(stateType,"^i") && strcmp(stateType,"^I")) ||
            (!wideReason && strcmp(reasonType,"^i") && strcmp(reasonType,"^I"))) return -1;
        uint64_t state=0,reason=0;
        ((void (*)(id,SEL,void *,void *))objc_msgSend)(manager,selector,&state,&reason);
        return state == 1023 ? 1 : (state == 1022 ? 0 : -1);
    } @catch (__unused NSException *error) { return -1; }
}
static inline BOOL NFBMISSetOff(id manager) {
    @try {
        SEL selector=NSSelectorFromString(@"setState:"); NSMethodSignature *sig=NFBSignature(manager,selector);
        if (!sig || sig.numberOfArguments != 3 || strcmp(NFBHotspotType(sig.methodReturnType),"v")) return NO;
        const char *type=NFBHotspotType([sig getArgumentTypeAtIndex:2]);
        if (!strcmp(type,"q") || !strcmp(type,"Q")) ((void (*)(id,SEL,long long))objc_msgSend)(manager,selector,1022);
        else if (!strcmp(type,"i") || !strcmp(type,"I")) ((void (*)(id,SEL,int))objc_msgSend)(manager,selector,1022);
        else return NO;
        return YES;
    } @catch (__unused NSException *error) { return NO; }
}
