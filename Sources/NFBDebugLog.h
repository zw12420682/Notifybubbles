// Shared, header-only diagnostic logger for both tweaks (NotifyBubbles and
// NotifyBubblesBack). Each dylib is injected into a different process class
// (SpringBoard vs the target app), so a header with static inline functions
// avoids linking a shared object between the two targets. Output goes to NSLog
// AND to the first writable path below, so the result can be inspected with
// Filza instead of a live log viewer.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

static inline NSArray<NSString *> *NFBDebugLogPaths(void) {
    static NSArray<NSString *> *paths = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *writable = [NSMutableArray array];
        NSArray<NSString *> *candidates = @[
            @"/var/tmp/nfb-debug.log",
            @"/var/mobile/Library/Logs/nfb-debug.log",
            [NSTemporaryDirectory() stringByAppendingPathComponent:@"nfb-debug.log"],
        ];
        for (NSString *candidate in candidates) {
            FILE *file = fopen(candidate.fileSystemRepresentation, "a");
            if (!file) continue;
            fclose(file);
            [writable addObject:candidate];
        }
        paths = writable;
    });
    return paths;
}

static inline void NFBDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[NFB] %@", message);
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"%@ [%@ pid=%d] %@\n",
                      [formatter stringFromDate:NSDate.date],
                      NSProcessInfo.processInfo.processName, getpid(), message];
    for (NSString *path in NFBDebugLogPaths()) {
        FILE *file = fopen(path.fileSystemRepresentation, "a");
        if (!file) continue;
        fputs(line.UTF8String, file);
        fclose(file);
    }
}

// Dump every method whose name contains one of the given lowercase keywords,
// with its type encoding. Used to discover the real TrollOpen control selectors
// instead of guessing names.
static inline void NFBDumpMethodList(Class cls, NSString *label, NSArray<NSString *> *keywords) {
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

