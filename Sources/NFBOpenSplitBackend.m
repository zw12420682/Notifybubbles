#import "NFBSplitCoordinator.h"
#import "NFBWindowControls.h"
#import "NFBDesktopHost.h"
#import "NFBWindowState.h"
@interface NFBOpenSplitBackend : NSObject <NFBSplitBackend> @end
@implementation NFBOpenSplitBackend
- (NSString *)identifier { return @"open-compat"; }
- (NSString *)sceneIdentity { return [NSString stringWithFormat:@"%@|%p",NFBCurrentWindowState().sceneKey ?: @"unknown",NFBCurrentWindowState().floatingWindow]; }
- (BOOL)applyMovieEnabled:(BOOL)enabled { return NFBUpdateMovieMode(enabled); }
- (void)settleMovieKeyboard { NFBRecheckMovieLayout(); }
- (void)closeDesktop { NFBCloseDesktopSplit(); }
- (BOOL)replaceWindowWithDesktop:(UIView *)window { return NFBReplaceSplitWithDesktop(window); }
- (BOOL)desktopActive { return NFBDesktopSplitActive(); }
@end

id<NFBSplitBackend> NFBCreateOpenSplitBackend(void) { return [NFBOpenSplitBackend new]; }
