#import <Foundation/Foundation.h>
@interface NFBRecord : NSObject
@property(nonatomic, copy) NSString *appID;
@property(nonatomic, copy) NSString *notificationID;
@property(nonatomic, strong) id request;
@property(nonatomic, strong) id destination;
@property(nonatomic, strong) NSDate *timestamp;
@property(nonatomic, copy) NSString *revision;
@end
// Main-thread confined. Notification queues are independent of pinned icons.
@interface NFBStore : NSObject
@property(nonatomic, readonly) NSArray<NSString *> *appIDs;
@property(nonatomic, readonly) NSUInteger count;
- (BOOL)putApp:(NSString *)appID notification:(NSString *)notificationID request:(id)request destination:(id)destination;
- (void)promoteApp:(NSString *)appID;
- (void)pinApp:(NSString *)appID;
- (NFBRecord *)latestForApp:(NSString *)appID;
- (NSUInteger)countForApp:(NSString *)appID;
- (void)consumeRecord:(NFBRecord *)record;
- (void)removeApp:(NSString *)appID notification:(NSString *)notificationID;
- (void)removeApp:(NSString *)appID;
- (void)closeApp:(NSString *)appID;
- (void)clear;
@end
