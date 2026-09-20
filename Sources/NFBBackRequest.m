#import "NFBBackRequest.h"
#import "NFBBackProtocol.h"
#import "NFBDebugLog.h"
#include <notify.h>
void NFBRequestAppBack(NSString *app, void (^completion)(NSInteger, NSInteger)) {
    NSCAssert(NSThread.isMainThread, @"Back requests must be sent on main thread");
    if (!app.length) { completion(-1, 0); return; }
    NSString *name = NFBBackName(app);
    NSString *reply = [name stringByAppendingString:@".reply"];
    int requestToken = 0;
    if (notify_register_check(name.UTF8String, &requestToken) != NOTIFY_STATUS_OK) {
        NFBDebugLog(@"back: request register_check failed for %@", app);
        completion(-1, 0); return;
    }
    uint64_t request = NFBBackTime();
    __block int replyToken = 0;
    __block BOOL finished = NO;
    uint32_t status = notify_register_dispatch(reply.UTF8String, &replyToken, dispatch_get_main_queue(), ^(int token) {
        if (finished) return;
        uint64_t state = 0;
        if (notify_get_state(token, &state) != NOTIFY_STATUS_OK || (state >> NFBBackStatusShift) != request) return;
        finished = YES;
        notify_cancel(replyToken); notify_cancel(requestToken);
        NSInteger reason = (NSInteger)(state & 0xF);
        NFBDebugLog(@"back: reply status=%ld (0=ok 1=noWindow 2=noBackAction 3=customItem 4=transitioning 5=exception)",
                    (long)reason);
        completion(reason == NFBBackStatusPerformed ? 1 : 0, reason);
    });
    if (status != NOTIFY_STATUS_OK) {
        NFBDebugLog(@"back: reply register_dispatch failed status=%u", status);
        notify_cancel(requestToken); completion(-1, 0); return;
    }
    if (notify_set_state(requestToken, request) != NOTIFY_STATUS_OK || notify_post(name.UTF8String) != NOTIFY_STATUS_OK) {
        NFBDebugLog(@"back: set_state/post failed for %@", app);
        finished = YES; notify_cancel(replyToken); notify_cancel(requestToken); completion(-1, 0); return;
    }
    NFBDebugLog(@"back: posted request=%llu name=%@", request, name);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (finished) return;
        finished = YES; notify_cancel(replyToken); notify_cancel(requestToken);
        NFBDebugLog(@"back: timed out waiting for %@", app);
        completion(-1, 0);
    });
}
