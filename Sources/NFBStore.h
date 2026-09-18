#import <Foundation/Foundation.h>

// Main-thread confined. Badges are deliberately not notification counts.
@interface NFBRecord : NSObject
@property(nonatomic, copy) NSString *appID;
@property(nonatomic, copy) NSString *notificationID;
@property(nonatomic, strong) id request;
@property(nonatomic, strong) id destination;
@end

@interface NFBStore : NSObject
@property(nonatomic, readonly) NSArray<NSString *> *appIDs;
@property(nonatomic, readonly) NSUInteger count;
- (void)putApp:(NSString *)appID notification:(NSString *)notificationID
       request:(id)request destination:(id)destination;
- (NFBRecord *)latestForApp:(NSString *)appID;
- (NFBRecord *)actionForApp:(NSString *)appID;
- (void)removeApp:(NSString *)appID notification:(NSString *)notificationID;
- (void)removeApp:(NSString *)appID;
- (void)closeApp:(NSString *)appID;
- (void)clear;
@end
