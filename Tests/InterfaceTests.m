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
static void Check(BOOL ok) { if (!ok) abort(); }
int main(void) {
 @autoreleasepool {
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
