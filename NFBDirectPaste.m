#import "NFBDirectPaste.h"
#import <objc/message.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>
#import <time.h>
// Darwin libSystem exports proc_pidpath on iOS; public iPhone SDKs omit libproc.h.
extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#import <fcntl.h>
#import <poll.h>

static BOOL NFBPasteAllowed(NSString *bundle) {
    return [bundle isEqualToString:@"com.apple.mobilenotes"] || [bundle isEqualToString:@"com.openminis.app"];
}
static id NFBPasteObject(id object, NSString *name, id arg) {
    @try {
        SEL sel = NSSelectorFromString(name);
        NSMethodSignature *sig = [object methodSignatureForSelector:sel];
        if (!sig || sig.methodReturnType[0] != '@' || sig.numberOfArguments != (arg ? 3 : 2)) return nil;
        if (arg && [sig getArgumentTypeAtIndex:2][0] != '@') return nil;
        return arg ? ((id (*)(id, SEL, id))objc_msgSend)(object, sel, arg) :
                     ((id (*)(id, SEL))objc_msgSend)(object, sel);
    } @catch (__unused NSException *exception) { return nil; }
}
static int NFBPastePID(NSString *bundle) {
    @try {
        id service = NFBPasteObject(NSClassFromString(@"FBSSystemService"), @"sharedService", nil);
        SEL sel = NSSelectorFromString(@"pidForApplication:");
        NSMethodSignature *sig = [service methodSignatureForSelector:sel];
        if (sig.numberOfArguments == 3 && sig.methodReturnType[0] == 'i' && [sig getArgumentTypeAtIndex:2][0] == '@')
            return ((int (*)(id, SEL, id))objc_msgSend)(service, sel, bundle);
    } @catch (__unused NSException *exception) {}
    return 0;
}
static NSString *NFBPastePath(NSString *container, int pid) {
    if (![container hasPrefix:@"/"] || pid < 2) return nil;
    return [container stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp/.nfbp.%d", pid]];
}
NSDictionary *NFBPasteFrontTarget(void) {
    if (!NSThread.isMainThread || !UIApplication.sharedApplication.protectedDataAvailable) return nil;
    id app = NFBPasteObject(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication", nil);
    id bundle = NFBPasteObject(app, @"bundleIdentifier", nil);
    if (![bundle isKindOfClass:NSString.class] || !NFBPasteAllowed(bundle)) return nil;
    int pid = NFBPastePID(bundle);
    id proxy = NFBPasteObject(NSClassFromString(@"LSApplicationProxy"), @"applicationProxyForIdentifier:", bundle);
    id url = NFBPasteObject(proxy, @"dataContainerURL", nil);
    NSString *container = [url isKindOfClass:NSURL.class] && [url isFileURL] ? [url path] : nil;
    if (!container) {
        id path = NFBPasteObject(proxy, @"dataContainerPath", nil);
        if ([path isKindOfClass:NSString.class]) container = path;
    }
    NSString *path = NFBPastePath(container, pid);
    return path ? @{@"path":path, @"pid":@(pid), @"bundle":bundle} : nil;
}
static BOOL NFBPasteSockAddr(NSString *path, struct sockaddr_un *addr) {
    const char *bytes = path.fileSystemRepresentation;
    if (!bytes || strlen(bytes) >= sizeof(addr->sun_path)) return NO;
    memset(addr, 0, sizeof(*addr));
    addr->sun_family = AF_UNIX;
    memcpy(addr->sun_path, bytes, strlen(bytes) + 1);
    addr->sun_len = SUN_LEN(addr);
    return YES;
}
static int NFBPastePeer(int fd) {
    pid_t peer = 0;
    socklen_t size = sizeof(peer);
    return getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peer, &size) == 0 ? peer : 0;
}
static BOOL NFBPasteSpringBoardPeer(int fd) {
    char path[4096] = {0};
    int pid = NFBPastePeer(fd);
    return pid > 1 && proc_pidpath(pid, path, sizeof(path)) > 0 &&
        strcmp(path, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0;
}
static void NFBPasteSocketFlags(int fd) {
    int yes = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
    (void)fcntl(fd, F_SETFL, O_NONBLOCK);
}
static BOOL NFBPasteIO(int fd, void *buffer, size_t size, BOOL writing, int timeout) {
    struct pollfd p = {fd, writing ? POLLOUT : POLLIN, 0};
    if (poll(&p, 1, timeout) != 1 || !(p.revents & p.events)) return NO;
    ssize_t bytes = writing ? send(fd, buffer, size, 0) : recv(fd, buffer, size, MSG_WAITALL);
    return bytes == (ssize_t)size;
}
static uint64_t NFBPasteClock(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW); }
struct NFBPastePacket { uint64_t deadline; int64_t changeCount; };
BOOL NFBPasteRequest(NSDictionary *target) {
    if (!target || NSThread.isMainThread) return NO;
    struct sockaddr_un addr;
    if (!NFBPasteSockAddr(target[@"path"], &addr)) return NO;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    NFBPasteSocketFlags(fd);
    BOOL success = NO;
    if (connect(fd, (const struct sockaddr *)&addr, addr.sun_len) == 0 && NFBPastePeer(fd) == [target[@"pid"] intValue]) {
        struct NFBPastePacket packet = {[target[@"deadline"] unsignedLongLongValue], [target[@"changeCount"] longLongValue]};
        char reply = 0;
        if (packet.deadline > NFBPasteClock() && NFBPasteIO(fd, &packet, sizeof(packet), YES, 80) &&
            NFBPasteIO(fd, &reply, sizeof(reply), NO, 420)) success = reply == 1;
    }
    close(fd);
    return success;
}

static UIView *NFBPasteFocused(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01) return nil;
    if (view.isFirstResponder) return view;
    for (UIView *child in view.subviews) {
        UIView *focus = NFBPasteFocused(child);
        if (focus) return focus;
    }
    return nil;
}
static BOOL NFBPasteInvoke(uint64_t deadline) {
    UIApplication *app = UIApplication.sharedApplication;
    if (NFBPasteClock() >= deadline || app.applicationState != UIApplicationStateActive || !app.protectedDataAvailable) return NO;
    UIWindow *key = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow && !window.hidden) {
            if (key) return NO;
            key = window;
        }
    }
    UIView *focus = NFBPasteFocused(key);
    SEL action = @selector(paste:);
    if (![focus conformsToProtocol:@protocol(UITextInput)] || !focus.isFirstResponder || focus.window != key ||
        ([focus respondsToSelector:@selector(isSecureTextEntry)] && [(id<UITextInputTraits>)focus isSecureTextEntry]) ||
        ![focus respondsToSelector:action] || ![focus canPerformAction:action withSender:nil] || NFBPasteClock() >= deadline) return NO;
    return [app sendAction:action to:focus from:nil forEvent:nil];
}
void NFBPasteInstallAppHelper(void) {
    if (!NFBPasteAllowed(NSBundle.mainBundle.bundleIdentifier)) return;
    static dispatch_source_t source;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = NFBPastePath(NSHomeDirectory(), getpid());
        struct sockaddr_un addr;
        if (!NFBPasteSockAddr(path, &addr)) return;
        int server = socket(AF_UNIX, SOCK_STREAM, 0);
        if (server < 0) return;
        NFBPasteSocketFlags(server);
        // No deletion of other paths. An existing endpoint means fail closed.
        if (bind(server, (const struct sockaddr *)&addr, addr.sun_len) != 0) { close(server); return; }
        if (chmod(addr.sun_path, 0600) != 0 || listen(server, 2) != 0) { unlink(addr.sun_path); close(server); return; }
        dispatch_queue_t queue = dispatch_queue_create("local.notifybubbles.direct-paste.helper", DISPATCH_QUEUE_SERIAL);
        source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)server, 0, queue);
        dispatch_source_set_event_handler(source, ^{
            int fd = accept(server, NULL, NULL);
            if (fd < 0) return;
            NFBPasteSocketFlags(fd);
            struct NFBPastePacket packet = {0};
            if (!NFBPasteSpringBoardPeer(fd) || !NFBPasteIO(fd, &packet, sizeof(packet), NO, 80) ||
                packet.deadline <= NFBPasteClock() || packet.deadline > NFBPasteClock() + 500000000 ||
                UIPasteboard.generalPasteboard.changeCount != packet.changeCount) { close(fd); return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                char reply = NFBPasteInvoke(packet.deadline) ? 1 : 0;
                // Nonblocking reply; never wait on the UI thread.
                (void)send(fd, &reply, sizeof(reply), 0);
                close(fd);
            });
        });
        dispatch_activate(source);
    });
}
