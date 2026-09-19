#import <Foundation/Foundation.h>
// result: 1 performed, 0 no supported back action, -1 no reply.
void NFBRequestAppBack(NSString *app, void (^completion)(NSInteger result));
