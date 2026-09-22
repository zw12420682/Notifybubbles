#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "NFBKeyboardState.h"
#include <stdatomic.h>
#include <string.h>

// This component only changes keyboard appearance; no input text is inspected.
static atomic_bool NFBForceDark;
static int stateToken = -1;
static NSHashTable<UIView *> *keyboardHosts;
static char savedStyleKey;
static void (*originalHostLayout)(UIView *, SEL);
static BOOL (*originalLightKeyboard)(id, SEL);
static BOOL renderLightKeyboard(id obj, SEL sel) {
    return atomic_load(&NFBForceDark) ? NO : originalLightKeyboard(obj, sel);
}
static void applyHostStyle(UIView *view) {
    NSNumber *saved = objc_getAssociatedObject(view, &savedStyleKey);
    if (atomic_load(&NFBForceDark)) {
        if (!saved) objc_setAssociatedObject(view, &savedStyleKey,
            @(view.overrideUserInterfaceStyle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (view.overrideUserInterfaceStyle != UIUserInterfaceStyleDark)
            view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    } else if (saved) {
        objc_setAssociatedObject(view, &savedStyleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.overrideUserInterfaceStyle = saved.integerValue;
    }
}
static void hostLayout(UIView *view, SEL sel) {
    [keyboardHosts addObject:view];
    applyHostStyle(view);
    originalHostLayout(view, sel);
}
static UIResponder *findResponder(UIView *view) {
    if (view.isFirstResponder) return view;
    for (UIView *child in view.subviews) {
        UIResponder *found = findResponder(child);
        if (found) return found;
    }
    return nil;
}
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
    uint64_t state = 0;
    if (stateToken != -1 && notify_get_state(stateToken, &state) == NOTIFY_STATUS_OK && (state == 1 || state == 2)) {
        enabled = state == 2; valid = true;
    }
    BOOL changed = atomic_exchange(&NFBForceDark, valid && enabled) != (valid && enabled);
    if (changed) dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *host in keyboardHosts.allObjects) {
            applyHostStyle(host);
            [host setNeedsLayout];
        }
        // Reload only the current responder, without resigning it or touching text.
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                UIResponder *responder = findResponder(window);
                if (responder) { [responder reloadInputViews]; return; }
            }
        }
    });
}
static void preferencesChanged(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    loadSettings();
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
        keyboardHosts = [NSHashTable weakObjectsHashTable];
        if (notify_register_dispatch(NFBKeyboardStateName, &stateToken,
                dispatch_get_main_queue(), ^(__unused int token) { loadSettings(); }) != NOTIFY_STATUS_OK)
            stateToken = -1;
        loadSettings();
        hookGetter(NSClassFromString(@"UITextInputTraits"), (IMP)traitsAppearance, &originalTraits);
        hookGetter(UITextField.class, (IMP)fieldAppearance, &originalField);
        hookGetter(UITextView.class, (IMP)textAppearance, &originalText);
        Class cls = NSClassFromString(@"UIKBRenderConfig");
        SEL light = NSSelectorFromString(@"lightKeyboard");
        Method lightMethod = class_getInstanceMethod(cls, light);
        if (lightMethod && method_getNumberOfArguments(lightMethod) == 2) {
            char type[16] = {0}; method_getReturnType(lightMethod, type, sizeof(type));
            if (!strcmp(type, @encode(BOOL)))
                MSHookMessageEx(cls, light, (IMP)renderLightKeyboard, (IMP *)&originalLightKeyboard);
        }
        Class host = NSClassFromString(@"UIInputSetHostView");
        if (host && [host isSubclassOfClass:UIView.class])
            MSHookMessageEx(host, @selector(layoutSubviews), (IMP)hostLayout, (IMP *)&originalHostLayout);
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
