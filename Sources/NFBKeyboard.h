#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
CGFloat NFBKeyboardTopInView(UIView *root);

// Whether a keyboard is on screen, as far as the SpringBoard process can tell.
//
// SpringBoard does NOT host a third party app's keyboard: that window
// (UIRemoteKeyboardWindow) lives in the app's own process, so UIKit's keyboard
// notifications never reach us for it. This combines every signal that IS
// available in-process, and any one of them is enough:
//   1. UIKeyboard(Will|Did)(Show|Hide) notifications — fired for keyboards
//      SpringBoard hosts itself (Spotlight, passcode, ...).
//   2. A visible keyboard-classed window among SpringBoard's own windows.
//   3. SBUIController reporting keyboard visibility directly, when the build
//      happens to expose such a method.
BOOL NFBKeyboardVisible(void);

// Install the observers once; later calls are ignored. `onChange` is invoked on
// the main queue whenever the combined state flips, so the caller can refresh.
void NFBKeyboardInstall(void (^onChange)(void));
