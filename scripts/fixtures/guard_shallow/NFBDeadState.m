// Fixture: state stored and never read back. Rule 4 must report it even when the
// clone has no history to compare against - the property is declared right here.
@interface NFBDeadState : NSObject
@end
@interface NFBDeadState ()
@property(nonatomic) BOOL showClearAll;
@end
@implementation NFBDeadState
- (void)load {
    self.showClearAll = YES;
}
@end
