#import <UIKit/UIKit.h>

// Main thread only: install helper only in the two test applications.
void NFBPasteInstallAppHelper(void);
// Main thread only: snapshot the supported frontmost application.
NSDictionary *NFBPasteFrontTarget(void);
// Worker only: exact, time-bounded socket request to that process.
BOOL NFBPasteRequest(NSDictionary *target);
