#pragma once
#import <UIKit/UIKit.h>

// Engine-specific scene APIs stay behind this contract. Future native engines
// must provide live interactive scenes, not snapshots masquerading as windows.
@protocol NFBSplitBackend <NSObject>
@property(nonatomic, readonly, copy) NSString *identifier;
- (NSString *)sceneIdentity;
- (BOOL)applyMovieEnabled:(BOOL)enabled;
- (void)settleMovieKeyboard;
- (void)closeDesktop;
- (BOOL)replaceWindowWithDesktop:(UIView *)window;
- (BOOL)desktopActive;
@end

typedef NS_ENUM(NSUInteger, NFBSplitPhase) {
    NFBSplitPhaseDisabled, NFBSplitPhaseLocked, NFBSplitPhaseNormal,
    NFBSplitPhaseMovie, NFBSplitPhaseMovieDesktop
};

@interface NFBSplitCoordinator : NSObject
+ (instancetype)shared;
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, readonly) NFBSplitPhase phase;
@property(nonatomic, readonly) BOOL movieActive;
// Called on main queue, before reading layout. No timers are created here.
- (void)updateEnabled:(BOOL)enabled locked:(BOOL)locked movie:(BOOL)movie keyboard:(BOOL)keyboard;
- (void)reconcile;
- (void)settleMovieKeyboard;
- (BOOL)replaceWindowWithDesktop:(UIView *)window;
- (void)closeDesktop;
// Engine replacement is explicit and rejected while a session is active.
- (BOOL)installBackend:(id<NFBSplitBackend>)backend;
@end
