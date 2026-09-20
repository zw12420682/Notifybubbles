#import <Foundation/Foundation.h>
#import "NFBStore.h"
#import "NFBBackProtocol.h"
#import "NFBGeometry.h"
#include <stdlib.h>
@interface TestRequest : NSObject
@property(nonatomic, strong) NSDate *timestamp;
@end
@implementation TestRequest
@end
static TestRequest *Request(double time) {
    TestRequest *r = [TestRequest new]; r.timestamp = [NSDate dateWithTimeIntervalSince1970:time]; return r;
}
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NFBStore *s = [NFBStore new]; id destination = [NSObject new];
        [s pinApp:@"switcherOnly"];
        Check(s.count == 0 && ![s latestForApp:@"switcherOnly"], @"Switcher card pins app without fabricating unread messages");
        [s putApp:@"chat" notification:@"new" request:Request(300) destination:destination];
        [s putApp:@"mail" notification:@"1" request:Request(250) destination:destination];
        [s putApp:@"chat" notification:@"old" request:Request(100) destination:destination];
        Check([s.appIDs isEqual:@[@"switcherOnly", @"chat", @"mail"]], @"Notification keeps its app's existing position");
        Check([[s latestForApp:@"chat"].notificationID isEqual:@"new"], @"Queue sorts by notification timestamp, not delivery timing");
        Check(![s putApp:@"chat" notification:@"new" request:Request(300) destination:destination] && s.count == 3, @"Duplicate system delivery is not a second notification");
        [s promoteApp:@"mail"];
        Check([s.appIDs.firstObject isEqual:@"mail"] && s.count == 3, @"Foreground promotion preserves unread queues");
        [s promoteApp:@"notPinned"];
        Check(![s.appIDs containsObject:@"notPinned"], @"Promotion cannot recreate a dismissed icon");
        [s promoteApp:@"chat"];
        NFBRecord *new = [s latestForApp:@"chat"];
        [s consumeRecord:new];
        Check([[s latestForApp:@"chat"].notificationID isEqual:@"old"], @"Second tap selects older message");
        Check([s latestForApp:@"mail"] != nil, @"Other app unread queue unchanged");
        Check(![s putApp:@"chat" notification:@"new" request:Request(300) destination:destination], @"Consumed duplicate cannot reenter queue");
        [s consumeRecord:[s latestForApp:@"chat"]];
        Check(![s latestForApp:@"chat"] && [s.appIDs containsObject:@"chat"], @"Empty queue keeps icon and selects ordinary launch");
        Check([s putApp:@"chat" notification:@"new" request:Request(400) destination:destination], @"Reused identifier with a new timestamp is a new message");
        NFBRecord *revision = [s latestForApp:@"chat"];
        [s putApp:@"chat" notification:@"new" request:Request(500) destination:destination];
        [s consumeRecord:revision];
        Check([s latestForApp:@"chat"].timestamp.timeIntervalSince1970 == 500, @"Completing old action cannot delete a newer revision");
        [s removeApp:@"chat" notification:@"new"];
        Check(![s latestForApp:@"chat"] && [s.appIDs containsObject:@"chat"], @"System withdrawal preserves pinned icon");
        [s closeApp:@"chat"];
        Check(![s.appIDs containsObject:@"chat"] && [s latestForApp:@"mail"], @"Closing one card leaves other cards intact");
        [s clear]; Check(s.count == 0 && s.appIDs.count == 0, @"Clear removes all queues and pins");
        for (NSUInteger i=0; i<600; i++)
            [s putApp:@"chat" notification:[NSString stringWithFormat:@"n%lu", (unsigned long)i] request:Request(i) destination:destination];
        Check(s.count == 512, @"Queue memory bounded");
        Check(NFBSize(1)==32 && NFBSize(200)==80 && NFBSize(NAN)==48, @"Size bounds and invalid input");
        Check(NFBOpacity(-1)==0.2 && NFBOpacity(5)==1 && NFBOpacity(NAN)==1, @"Opacity bounds and invalid input");
        for (int d=32; d<=80; d++) {
            double left=390-(d+14)+7+NFBRetraction(d);
            Check(fabs(390-left-d/2.0)<0.001, @"Half visible for all sizes");
        }
        Check(NFBPosition(-5) == 0 && NFBPosition(5) == 1 && NFBPosition(NAN) == 0.7, @"Position clamping");
        Check(NFBRowCenter(3, 0, 66, 62) == 163 && NFBRowCenter(3, 2, 66, 62) == 31, @"First icon is lowest");
        Check(NFBBackFresh(1000, 1200) && !NFBBackFresh(1000, 2600) && !NFBBackFresh(1300, 1200), @"Expired and future back requests rejected");
        NSLog(@"PASS: queue chronology, per-app isolation, deduplication, consumption, switcher pins and geometry");
    }
    return 0;
}
