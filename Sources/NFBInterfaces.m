#import "NFBInterfaces.h"

NSMethodSignature *NFBSignature(id object, SEL selector) {
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
