#import <Foundation/Foundation.h>
#import "NFBStateLedger.h"

int main(void) {
    @autoreleasepool {
        NFBStateLedger *ledger=[NFBStateLedger new]; NSObject *object=[NSObject new];
        __block NSInteger value=1; __block NSUInteger restored=0;
        [ledger remember:object key:@"value" restore:^{ value=1; restored++; }];
        value=2;
        [ledger remember:object key:@"value" restore:^{ value=2; restored++; }];
        [ledger remember:object key:@"throws" restore:^{ [NSException raise:@"Fixture" format:@"Expected restoration failure"]; }];
        [ledger restore];
        NSCAssert(value==1 && restored==1,@"First state survives duplicate capture and independent cleanup failure");
        [ledger restore]; NSCAssert(restored==1,@"Restore must be idempotent");
        __weak NSObject *weakObject;
        @autoreleasepool {
            NSObject *retained=[NSObject new]; weakObject=retained;
            [ledger remember:retained key:@"lifetime" restore:^{ (void)retained.description; }];
        }
        NSCAssert(weakObject!=nil,@"Ledger retains targets until restored");
        [ledger restore];
        NSCAssert(weakObject==nil,@"Restoration releases targets");
        NSLog(@"PASS: deduplication, exception isolation, idempotence and target lifetime");
    }
    return 0;
}
