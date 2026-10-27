// Fixture: the build mistake the guards exist for - a C struct declared as a bare
// variable inside a class extension ("cannot declare variable inside @interface or
// @protocol"). It must be an ivar in the @implementation.
@interface NFBVapor : NSObject
@end
@interface NFBVapor ()
@property(nonatomic) BOOL tickStateValid;
NFBProbeStamp probe;
@end
@implementation NFBVapor
@end
