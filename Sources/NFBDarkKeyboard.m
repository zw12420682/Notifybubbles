#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdatomic.h>
#include <string.h>

// This component only changes keyboard appearance; no input text is inspected.
static atomic_bool NFBForceDark;
typedef NSInteger (*NFBAppearanceGetter)(id, SEL);
static NFBAppearanceGetter originalTraits, originalField, originalText;
static NSInteger traitsAppearance(id obj, SEL sel) {
    return atomic_load(&NFBForceDark) ? UIKeyboardAppearanceDark : originalTraits(obj, sel);
}
static NSInteger fieldAppearance(id obj, SEL sel) {
    return atomic_load(&NFBForceDark) ? UIKeyboardAppearanceDark : originalField(obj, sel);
}
static NSInteger textAppearance(id obj, SEL sel) {
    return atomic_load(&NFBForceDark) ? UIKeyboardAppearanceDark : originalText(obj, sel);
}
static id (*originalConfig)(id, SEL, NSInteger, id);
static id keyboardConfig(id obj, SEL sel, NSInteger appearance, id mode) {
    return originalConfig(obj, sel, atomic_load(&NFBForceDark) ? UIKeyboardAppearanceDark : appearance, mode);
}
static void loadSettings(void) {
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    Boolean valid = false;
    Boolean enabled = CFPreferencesGetAppBooleanValue(CFSTR("DarkKeyboard"), CFSTR("local.notifybubbles"), &valid);
    atomic_store(&NFBForceDark, valid && enabled);
}
static void preferencesChanged(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    loadSettings();
    // The next keyboard presentation reads fresh traits. Do not change the
    // responder or overwrite its stored appearance, which must survive disable.
}
static void hookGetter(Class cls, IMP replacement, NFBAppearanceGetter *original) {
    SEL sel = @selector(keyboardAppearance);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != 2) return;
    char type[32] = {0}; method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, @encode(NSInteger))) return;
    MSHookMessageEx(cls, sel, replacement, (IMP *)original);
}
__attribute__((constructor)) static void NFBInstallDarkKeyboard(void) {
    @autoreleasepool {
        loadSettings();
        hookGetter(NSClassFromString(@"UITextInputTraits"), (IMP)traitsAppearance, &originalTraits);
        hookGetter(UITextField.class, (IMP)fieldAppearance, &originalField);
        hookGetter(UITextView.class, (IMP)textAppearance, &originalText);
        Class cls = NSClassFromString(@"UIKBRenderConfig");
        SEL sel = NSSelectorFromString(@"configForAppearance:inputMode:");
        NSMethodSignature *sig = [cls methodSignatureForSelector:sel];
        if (sig.numberOfArguments == 4 && sig.methodReturnType[0] == '@' &&
            !strcmp([sig getArgumentTypeAtIndex:2], @encode(NSInteger)) &&
            [sig getArgumentTypeAtIndex:3][0] == '@') {
            MSHookMessageEx(object_getClass(cls), sel, (IMP)keyboardConfig, (IMP *)&originalConfig);
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            preferencesChanged, CFSTR("local.notifybubbles/preferences.changed"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
