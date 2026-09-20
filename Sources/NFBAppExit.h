#import <Foundation/Foundation.h>

// End an app the way the App Switcher's swipe-up does: terminate its process.
// Runs in SpringBoard on the main thread. YES means a termination request was
// accepted, not that the app is already gone.
BOOL NFBTerminateApp(NSString *bundleID);
