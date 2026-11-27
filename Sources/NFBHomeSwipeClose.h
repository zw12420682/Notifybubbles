#pragma once
#import <Foundation/Foundation.h>
// Main queue only. Uses the existing master switch, without new preferences.
void NFBConfigureHomeSwipeClose(BOOL enabled);
void NFBInstallHomeSwipeClose(void);

void NFBObserveRejectedSwipeResult(void);
