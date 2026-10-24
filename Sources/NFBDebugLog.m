#import "NFBDebugLog.h"
#include <stdatomic.h>
#include <stdbool.h>

static atomic_bool verbose;
void NFBConfigureDebugLogging(BOOL enabled) { atomic_store(&verbose, enabled); }
BOOL NFBDebugLoggingEnabled(void) { return atomic_load(&verbose); }
static void NFBQueueLog(NSString *level, NSString *format, va_list arguments) {
    if ([level isEqualToString:@"debug"] && !NFBDebugLoggingEnabled()) return;
    static dispatch_queue_t queue;
    static dispatch_semaphore_t capacity;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("local.notifybubbles.logging", DISPATCH_QUEUE_SERIAL);
        capacity = dispatch_semaphore_create(256);
    });
    if (dispatch_semaphore_wait(capacity, DISPATCH_TIME_NOW)) return;
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    if (message.length > 4096) message = [message substringToIndex:4096];
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSLog(@"[NFB %@] %@", level, message);
            static NSString *path;
            static BOOL selected;
            static NSDateFormatter *formatter;
            if (!selected) {
                selected = YES;
                // Even after the rootless/roothide split /var/tmp stays one of the
                // few shared, world-writable paths (/var/jb and the RootHide
                // bootstrap root may be private to SpringBoard), so keep the
                // global file and fall back to the process container last.
                for (NSString *candidate in @[@"/var/tmp/nfb-debug.log",
                        @"/var/mobile/Library/Logs/nfb-debug.log",
                        [NSTemporaryDirectory() stringByAppendingPathComponent:@"nfb-debug.log"]]) {
                    FILE *probe = fopen(candidate.fileSystemRepresentation, "a");
                    if (probe) { fclose(probe); path = candidate; break; }
                }
            }
            if (!formatter) { formatter = [NSDateFormatter new]; formatter.dateFormat = @"MM-dd HH:mm:ss.SSS"; }
            if (path) {
                FILE *file = fopen(path.fileSystemRepresentation, "a");
                if (file) {
                    if (fseek(file, 0, SEEK_END) == 0 && ftell(file) >= 1024 * 1024) {
                        fclose(file);
                        NSString *previous = [path stringByAppendingString:@".previous"];
                        if (rename(path.fileSystemRepresentation, previous.fileSystemRepresentation) == 0)
                            file = fopen(path.fileSystemRepresentation, "a");
                        else file = NULL; // Don't let a failed rotation grow an unbounded file.
                    }
                    if (file) {
                        NSString *line = [NSString stringWithFormat:@"%@ pid=%d %@\n",
                            [formatter stringFromDate:NSDate.date], getpid(), message];
                        fputs(line.UTF8String, file); fclose(file);
                    }
                }
            }
        }
        dispatch_semaphore_signal(capacity);
    });
}
void NFBWriteDebugLog(NSString *format, ...) {
    va_list arguments; va_start(arguments, format); NFBQueueLog(@"debug", format, arguments); va_end(arguments);
}
void NFBErrorLog(NSString *format, ...) {
    va_list arguments; va_start(arguments, format); NFBQueueLog(@"error", format, arguments); va_end(arguments);
}

void NFBInfoLog(NSString *format, ...) {
    va_list arguments; va_start(arguments, format); NFBQueueLog(@"info", format, arguments); va_end(arguments);
}
