#pragma once
#import <Foundation/Foundation.h>
// Debug-only capture. Hooks remain passive and always invoke the original IMP.
void NFBArmWidgetDetachTrace(BOOL newLockCycle);
