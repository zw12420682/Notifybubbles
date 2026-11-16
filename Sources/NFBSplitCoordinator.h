#pragma once
#import <UIKit/UIKit.h>
@class NFBWindowLease;

// Engine-specific scene APIs stay behind this contract. Future native engines
// must provide live interactive scenes, not snapshots masquerading as windows.
typedef NS_ENUM(NSUInteger, NFBSplitSnapshotStatus) {
    NFBSplitSnapshotUnknown, NFBSplitSnapshotPresent, NFBSplitSnapshotAbsent
};
@interface NFBSplitSnapshot : NSObject
@property(nonatomic,copy) NSString *sceneIdentity, *lowerApp;
@property(nonatomic,weak) UIView *lowerWindow;
@property(nonatomic) CGRect lowerFrame;
@property(nonatomic) CGSize rootSize;
@property(nonatomic) NSUInteger desktopSessionIdentifier;
@property(nonatomic) NFBSplitSnapshotStatus status;
@end

@protocol NFBSplitBackend <NSObject>
@property(nonatomic, readonly, copy) NSString *identifier;
- (NSString *)sceneIdentity;
- (NFBSplitSnapshot *)captureLayoutInView:(UIView *)root;
- (void)restorePortraitPlacement;
- (BOOL)applyMovieEnabled:(BOOL)enabled;
- (void)settleMovieKeyboard;
- (void)closeDesktop;
- (BOOL)replaceWindowWithDesktop:(UIView *)window;
- (BOOL)desktopActive;
- (NSUInteger)desktopSessionIdentifier;
- (BOOL)recheckDesktopAfterCleanup:(NSArray<NSString *> *)apps;
@end

typedef NS_ENUM(NSUInteger, NFBSplitPhase) {
    NFBSplitPhaseDisabled, NFBSplitPhaseLocked, NFBSplitPhaseNormal,
    NFBSplitPhaseMovie, NFBSplitPhaseMovieDesktop
};

@interface NFBSplitCoordinator : NSObject
+ (instancetype)shared;
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, strong, readonly) NFBWindowLease *windowLease;
@property(nonatomic, readonly) NFBSplitPhase phase;
@property(nonatomic, readonly) BOOL movieActive;
// Called on main queue, before reading layout. No timers are created here.
- (void)updateEnabled:(BOOL)enabled locked:(BOOL)locked movie:(BOOL)movie keyboard:(BOOL)keyboard;
- (void)reconcile;
- (void)settleMovieKeyboard;
- (void)scheduleMovieKeyboardChecks;
- (void)schedulePortraitRestoreAfter:(NSTimeInterval)delay;
- (NFBSplitSnapshot *)captureLayoutInView:(UIView *)root;
- (BOOL)keyboardRailFitsSnapshot:(NFBSplitSnapshot *)snapshot;
// Guard is read on main queue before every attempt, preserving notification and
// foreground cleanup cancellation. Scheduling/cancellation lives in the core.
- (void)scheduleDesktopAfterCleanup:(NSArray<NSString *> *)apps delay:(NSTimeInterval)delay
    guard:(BOOL (^)(void))guard refresh:(void (^)(void))refresh;
- (BOOL)replaceWindowWithDesktop:(UIView *)window;
- (void)closeDesktop;
// Engine replacement is explicit and rejected while a session is active.
- (BOOL)installBackend:(id<NFBSplitBackend>)backend;
@end
