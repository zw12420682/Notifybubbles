// Fixture: the four state shapes 0.48.88 added (drag clock, tick dirty state,
// layout recording, same-round floating id), all of them read back. Rule 4 must
// stay quiet about every one of them.
@interface NFBGoodState : NSObject
@end
@interface NFBGoodState ()
@property(nonatomic) BOOL favoriteDragConsumed;
@property(nonatomic) BOOL tickForcedRefresh;
@property(nonatomic) BOOL layoutRecording;
@property(nonatomic, copy) NSString *tickActiveFloating;
@end
@implementation NFBGoodState
- (void)load {
    self.layoutRecording = YES;
    self.tickForcedRefresh = YES;
    self.favoriteDragConsumed = YES;
    self.tickActiveFloating = @"a";
    if (self.layoutRecording) {}
    BOOL dirty = self.tickForcedRefresh;
    BOOL taken = self.favoriteDragConsumed;
    NSString *now = self.tickActiveFloating;
}
@end

// Fixture: dictionary element reads are reads, element writes are not. The same
// property is transcribed once as a key and once as a value; both are reads.
@interface NFBSlotState : NSObject
@end
@interface NFBSlotState ()
@property(nonatomic) BOOL columnSliding;
@end
@implementation NFBSlotState
- (id)value {
    NSMutableDictionary *slots = [NSMutableDictionary dictionary];
    slots[@"slide"] = @(self.columnSliding);
    return slots[self.columnSliding ? @"a" : @"b"];
}
@end
