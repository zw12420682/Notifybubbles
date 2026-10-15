#import <Foundation/Foundation.h>
#import "NFBBackProtocol.h"
// result: 1 performed, 0 not performed, -1 no reply (timeout or registration failed).
// reason: an NFBBackStatus value explaining why it was not performed.
void NFBRequestAppBack(NSString *app, void (^completion)(NSInteger result, NSInteger reason));
