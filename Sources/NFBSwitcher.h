#import <Foundation/Foundation.h>
// nil means unavailable/unknown, not an empty switcher.
NSArray<NSString *> *NFBReadSwitcherApps(void);
// Returns whether a native card-quit request was invoked, not whether removal
// already completed. A layout containing either protected app is never quit.
BOOL NFBQuitSwitcherCard(NSString *bundleID, NSString *front, NSString *floating);
