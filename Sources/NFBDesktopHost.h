#pragma once
#import <UIKit/UIKit.h>
// Hosts the existing system desktop view; does not create an application scene.
BOOL NFBShowDesktopInSplit(UIView *anchor);
BOOL NFBDesktopSplitActive(void);
// Read the committed pane radius, not a later portrait measurement.
CGFloat NFBDesktopSplitCornerRadius(void);
void NFBCloseDesktopSplit(void);
void NFBUpdateDesktopSplit(BOOL allowed);

NSString *NFBDesktopSplitError(void);
NSString *NFBConsumeDesktopSplitFailure(void);

// Scoped to auto movie desktop session; empty list restores borrowed levels.
void NFBUpdateMovieDesktopTouchHosts(NSArray<UIWindow *> *hosts);

// Explicit house action: close only the supplied portrait window, never its process.
BOOL NFBReplaceSplitWithDesktop(UIView *window);
BOOL NFBReplaceMoviePaneWithDesktop(UIView *window, NSUInteger retainedSession);
BOOL NFBReplaceMoviePaneWithAnchor(UIView *window, NSUInteger retainedSession, UIView *anchor);
UIView *NFBDesktopIndependentAnchor(void);

// Read-only lock/unlock widget observations; never mutates desktop or pages.
void NFBObserveHomeWidgetLockDiagnostics(BOOL locked, BOOL enabled);

NSUInteger NFBDesktopSessionIdentifier(void);
// Only a movie-owned session may park; identity guards against stale callers.
void NFBSetMovieDesktopParked(NSUInteger identifier, BOOL parked);
BOOL NFBMovieDesktopParked(void);

void NFBPublishMovieTouchWindows(NSArray<UIView *> *windows, NSUInteger desktopSession);

// Visual-only auto-movie exit. Real desktop is restored synchronously.
void NFBCloseMovieDesktopWithTransition(NSUInteger identifier);
void NFBUpdateDesktopReturnTransition(BOOL allowed);
