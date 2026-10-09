// Central asynchronous logger; verbose diagnostics are opt-in.
// Error reports remain available; one writable file is rotated at 1 MiB.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

void NFBConfigureDebugLogging(BOOL enabled);
BOOL NFBDebugLoggingEnabled(void);
void NFBDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void NFBErrorLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Dump every method whose name contains one of the given lowercase keywords,
// with its type encoding. Used to discover the real TrollOpen control selectors
// instead of guessing names.
static inline void NFBDumpMethodList(Class cls, NSString *label, NSArray<NSString *> *keywords) {
    if (!NFBDebugLoggingEnabled()) return;
    if (!cls) { NFBDebugLog(@"%@: <nil>", label); return; }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NFBDebugLog(@"%@ %@ (%u methods)", label, NSStringFromClass(cls), count);
    for (unsigned int index = 0; methods && index < count; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        NSString *lower = name.lowercaseString;
        for (NSString *keyword in keywords) {
            if ([lower containsString:keyword]) {
                NFBDebugLog(@"  %@ -%@ (%s)", label, name, method_getTypeEncoding(methods[index]));
                break;
            }
        }
    }
    if (methods) free(methods);
}
// Dump an object's instance methods, plus the class methods when `isClass` is YES
// (class methods live on the metaclass, so they need object_getClass).
static inline void NFBDumpMethods(id object, BOOL isClass, NSString *label, NSArray<NSString *> *keywords) {
    if (!object) { NFBDebugLog(@"%@: <nil>", label); return; }
    Class cls = isClass ? (Class)object : [object class];
    NFBDumpMethodList(cls, label, keywords);
    if (isClass && object_getClass(cls))
        NFBDumpMethodList(object_getClass(cls), [label stringByAppendingString:@"(class)"], keywords);
}

