#pragma once
#import <UIKit/UIKit.h>
@interface NFBWindowState : NSObject
@property(nonatomic) BOOL home;
@property(nonatomic) BOOL fullscreen;
@property(nonatomic) BOOL mini;
@property(nonatomic, copy) NSString *frontApp;
@property(nonatomic, copy) NSString *floatingApp;
@property(nonatomic, weak) UIView *floatingWindow;
@property(nonatomic, copy) NSString *sceneKey;
@end
// A snapshot is shared only until the next main-queue turn. Actions explicitly
// invalidate it, so caching cannot retain old window state across user commands.
NFBWindowState *NFBCurrentWindowState(void);
void NFBInvalidateWindowState(void);
