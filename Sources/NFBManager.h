#import <UIKit/UIKit.h>
@interface NFBManager : NSObject
+ (instancetype)shared;
- (void)receiveRequest:(id)request destination:(id)destination;
- (void)withdrawRequest:(id)request;
- (void)removeSection:(NSString *)section;
- (void)reloadPreferences;
- (void)clear;
@end
