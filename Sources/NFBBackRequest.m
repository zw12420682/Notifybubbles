#import "NFBBackRequest.h"
#import "NFBBackProtocol.h"
#include <notify.h>
void NFBRequestAppBack(NSString *app, void (^completion)(NSInteger)) {
    NSCAssert(NSThread.isMainThread, @"Back requests must be sent on main thread");
    if (!app.length) { completion(-1); return; }
    NSString *name = NFBBackName(app);
    NSString *reply = [name stringByAppendingString:@".reply"];
    int requestToken = 0;
    if (notify_register_check(name.UTF8String, &requestToken) != NOTIFY_STATUS_OK) { completion(-1); return; }
    uint64_t request = NFBBackTime();
    __block int replyToken = 0;
    __block BOOL finished = NO;
    uint32_t status = notify_register_dispatch(reply.UTF8String, &replyToken, dispatch_get_main_queue(), ^(int token) {
        if (finished) return;
        uint64_t state = 0;
        if (notify_get_state(token, &state) != NOTIFY_STATUS_OK || (state >> 2) != request) return;
        finished = YES;
        notify_cancel(replyToken); notify_cancel(requestToken);
        completion((state & 3) == 1 ? 1 : 0);
    });
    if (status != NOTIFY_STATUS_OK) { notify_cancel(requestToken); completion(-1); return; }
    if (notify_set_state(requestToken, request) != NOTIFY_STATUS_OK || notify_post(name.UTF8String) != NOTIFY_STATUS_OK) {
        finished = YES; notify_cancel(replyToken); notify_cancel(requestToken); completion(-1); return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (finished) return;
        finished = YES; notify_cancel(replyToken); notify_cancel(requestToken); completion(-1);
    });
}
