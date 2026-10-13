#import "NFBHotspotAdapters.h"
#import "NFBSystemDesktop.h"
#import "NFBExitInvocation.h"
#include <stdlib.h>
@interface Fixture : NSObject
@property(nonatomic) NSUInteger calls;
- (id)objectValue;
- (NSInteger)integerValue;
- (id)throwingValue;
+ (id)classValue;
- (void)accept:(id)process reason:(NSInteger)reason report:(BOOL)report description:(id)text;
- (BOOL)deny:(id)process;
- (NSInteger)wrong:(id)process;
- (BOOL)badArgument:(double)process;
- (void)throwingExit:(id)process;
@end
@implementation Fixture
- (id)objectValue { return @"value"; }
- (NSInteger)integerValue { self.calls++; return 42; }
- (id)throwingValue { [NSException raise:@"Fixture" format:@"expected"]; return nil; }
+ (id)classValue { return @"class"; }
- (void)accept:(id)process reason:(NSInteger)reason report:(BOOL)report description:(id)text {
    if (!process || reason != 1 || report || ![text isEqual:@"NotifyBubbles exit"]) abort();
    self.calls++;
}
- (BOOL)deny:(__unused id)process { self.calls++; return NO; }
- (NSInteger)wrong:(__unused id)process { self.calls++; return 1; }
- (BOOL)badArgument:(__unused double)process { self.calls++; return YES; }
- (void)throwingExit:(__unused id)process { [NSException raise:@"Fixture" format:@"expected"]; }
@end
@interface HotspotFixture : NSObject {
@public int _numberOfNetworkTetheredDevices;
}
@property(nonatomic) int state;
@property(nonatomic) int calls;
- (void)getState:(int *)state andReason:(int *)reason;
- (void)setState:(int)state;
@end
@implementation HotspotFixture
- (void)getState:(int *)state andReason:(int *)reason { *state=_state; *reason=0; }
- (void)setState:(int)state { _state=state; _calls++; }
@end
@interface BadHotspotFixture : NSObject
@property(nonatomic) int calls;
- (BOOL)numberOfNetworkTetheredDevices;
- (void)setState:(id)value;
@end
@implementation BadHotspotFixture
- (BOOL)numberOfNetworkTetheredDevices { _calls++; return NO; }
- (void)setState:(__unused id)value { _calls++; }
@end
static void Check(BOOL ok) { if (!ok) abort(); }
int main(void) {
 @autoreleasepool {
    Check(NFBIsSystemDesktop(@"com.apple.springboard"));
    Check(!NFBIsSystemDesktop(@"com.example.app") && !NFBIsSystemDesktop(nil));
    HotspotFixture *hotspot=[HotspotFixture new]; long long clients=-1;
    hotspot->_numberOfNetworkTetheredDevices=2;
    Check(NFBHotspotClientCount(hotspot,&clients) && clients==2);
    hotspot->_numberOfNetworkTetheredDevices=-1; Check(!NFBHotspotClientCount(hotspot,&clients));
    hotspot.state=1023; hotspot.calls=0; Check(NFBMISState(hotspot)==1);
    Check(NFBMISSetOff(hotspot) && hotspot.state==1022 && hotspot.calls==1);
    Check(NFBMISState(hotspot)==0); hotspot.state=42; Check(NFBMISState(hotspot)==-1);
    BadHotspotFixture *bad=[BadHotspotFixture new];
    Check(!NFBHotspotClientCount(bad,&clients) && bad.calls==0);
    Check(!NFBMISSetOff(bad) && bad.calls==0);
    Fixture *fixture = [Fixture new]; id process = [NSObject new];
    Check([NFBCheckedObject(fixture,@"objectValue") isEqual:@"value"]);
    Check([NFBCheckedObject(Fixture.class,@"classValue") isEqual:@"class"]);
    Check(!NFBCheckedObject(fixture,@"integerValue") && fixture.calls == 0);
    Check(NFBCheckedBool(fixture,@"integerValue",YES) && fixture.calls == 0);
    Check(!NFBCheckedBool(fixture,@"objectValue",NO));
    Check(!NFBCheckedObject(fixture,@"missing") && !NFBCheckedObject(fixture,@"throwingValue"));
    Check(NFBSignature(fixture,@selector(objectValue)) == NFBSignature(fixture,@selector(objectValue)));
    Check(!NFBInvokeTerminate(fixture,@selector(wrong:),process) && fixture.calls == 0);
    Check(!NFBInvokeTerminate(fixture,@selector(badArgument:),process) && fixture.calls == 0);
    Check(!NFBInvokeTerminate(fixture,@selector(deny:),process) && fixture.calls == 1);
    Check(NFBInvokeTerminate(fixture,@selector(accept:reason:report:description:),process) && fixture.calls == 2);
    Check(!NFBInvokeTerminate(fixture,@selector(throwingExit:),process));
    NFBConfigureDebugLogging(NO); Check(!NFBDebugLoggingEnabled());
    NFBConfigureDebugLogging(YES); Check(NFBDebugLoggingEnabled());
    puts("PASS: getter ABI, class methods, signature cache, termination rejection and logger switch");
 }
 return 0;
}
