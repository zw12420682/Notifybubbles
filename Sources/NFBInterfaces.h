#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

// Cache by runtime class (including metaclasses) and selector. Successful
// encodings stay valid when another tweak changes an IMP with the same ABI.
static inline NSMethodSignature *NFBSignature(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    static NSMapTable *classes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ classes = [NSMapTable strongToStrongObjectsMapTable]; });
    Class cls = object_getClass(object);
    NSString *name = NSStringFromSelector(selector);
    @synchronized (classes) {
        NSMutableDictionary *methods = [classes objectForKey:cls];
        NSMethodSignature *signature = methods[name];
        if (signature) return signature;
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) return [object methodSignatureForSelector:selector]; // forwarding: don't cache
        signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (!methods) { methods = [NSMutableDictionary dictionary]; [classes setObject:methods forKey:cls]; }
        if (signature) methods[name] = signature;
        return signature;
    }
}
static inline BOOL NFBObjectGetterCompatible(id object, SEL selector) {
    NSMethodSignature *signature = NFBSignature(object, selector);
    return signature && signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@';
}
static inline id NFBCheckedObject(id object, NSString *name) {
    @try {
        SEL selector = NSSelectorFromString(name);
        if (!NFBObjectGetterCompatible(object, selector)) return nil;
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *error) { return nil; }
}
static inline BOOL NFBBooleanGetterCompatible(id object, SEL selector) {
    NSMethodSignature *signature = NFBSignature(object, selector);
    return signature && signature.numberOfArguments == 2 &&
        (signature.methodReturnType[0] == 'B' || signature.methodReturnType[0] == 'c');
}
static inline BOOL NFBCheckedBool(id object, NSString *name, BOOL fallback) {
    @try {
        SEL selector = NSSelectorFromString(name);
        if (!NFBBooleanGetterCompatible(object, selector)) return fallback;
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *error) { return fallback; }
}
