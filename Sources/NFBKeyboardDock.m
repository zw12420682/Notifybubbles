#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "NFBKeyboardDockPolicy.h"
#include <string.h>

static BOOL customHeight, hideGlobe, hideVoice;
static double requestedHeight=34;
static NSMapTable<UIView *,NSNumber *> *hiddenButtons;
static id DockObject(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name);
    NSMethodSignature *sig=[object methodSignatureForSelector:selector];
    if (sig.numberOfArguments!=2 || sig.methodReturnType[0]!='@') return nil;
    @try { return ((id (*)(id,SEL))objc_msgSend)(object,selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static void DockRestoreButtons(void) {
    for (UIView *button in hiddenButtons.keyEnumerator.allObjects) button.hidden=[[hiddenButtons objectForKey:button] boolValue];
    [hiddenButtons removeAllObjects];
}
static void DockLoad(void) {
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    CFStringRef domain=CFSTR("local.notifybubbles");
    id height=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("KeyboardBottomHeight"),domain));
    id enabled=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("KeyboardBottomEnabled"),domain));
    id globe=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("KeyboardHideGlobe"),domain));
    id voice=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("KeyboardHideVoice"),domain));
    DockRestoreButtons();
    customHeight=[enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
    requestedHeight=[height isKindOfClass:NSNumber.class] ? [height doubleValue] : 34;
    hideGlobe=[globe isKindOfClass:NSNumber.class] && [globe boolValue];
    hideVoice=[voice isKindOfClass:NSNumber.class] && [voice boolValue];
}
static void DockChanged(__unused CFNotificationCenterRef center,__unused void *observer,__unused CFStringRef name,__unused const void *object,__unused CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ DockLoad(); });
}
static UIEdgeInsets (*originalPadding)(id,SEL,NSInteger,id);
static UIEdgeInsets DockPadding(id object,SEL selector,NSInteger orientation,id mode) {
    UIEdgeInsets insets=originalPadding(object,selector,orientation,mode);
    insets.bottom=NFBKeyboardDockBottom(insets.bottom,customHeight,requestedHeight,orientation==1 || orientation==2);
    return insets;
}
static UIEdgeInsets (*originalSceneInsets)(id,SEL);
static UIEdgeInsets DockSceneInsets(id object,SEL selector) {
    UIEdgeInsets insets=originalSceneInsets(object,selector);
    CGSize size=UIScreen.mainScreen.bounds.size;
    insets.bottom=NFBKeyboardDockBottom(insets.bottom,customHeight,requestedHeight,size.height>size.width);
    return insets;
}
static void DockHideItem(UIView *dock,NSString *getter,BOOL hide) {
    if (!hide) return;
    id item=DockObject(dock,getter);
    id button=DockObject(item,@"button");
    if (![button isKindOfClass:UIView.class] || ![(UIView *)button isDescendantOfView:dock]) return;
    if (![hiddenButtons objectForKey:button]) [hiddenButtons setObject:@([(UIView *)button isHidden]) forKey:button];
    [(UIView *)button setHidden:YES];
}
static void (*originalLayout)(UIView *,SEL);
static void DockLayout(UIView *dock,SEL selector) {
    originalLayout(dock,selector);
    if (hideGlobe) DockHideItem(dock,@"leftDockItem",YES);
    if (hideVoice) DockHideItem(dock,@"rightDockItem",YES);
}
static Method DockMethod(Class cls,SEL selector,const char *result,NSUInteger arguments) {
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return NULL;
    NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return sig.numberOfArguments==arguments && !strcmp(sig.methodReturnType,result) ? method : NULL;
}
__attribute__((constructor)) static void DockStart(void) {
    @autoreleasepool {
        // A separate UIKit filter; no manager, window scans, timers or logs in apps.
        if (UIDevice.currentDevice.userInterfaceIdiom!=UIUserInterfaceIdiomPhone) return;
        hiddenButtons=[NSMapTable weakToStrongObjectsMapTable];
        DockLoad();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,DockChanged,
            CFSTR("local.notifybubbles/preferences.changed"),NULL,CFNotificationSuspensionBehaviorCoalesce);
        Class impl=object_getClass(NSClassFromString(@"UIKeyboardImpl"));
        SEL padding=NSSelectorFromString(@"deviceSpecificPaddingForInterfaceOrientation:inputMode:");
        Method method=DockMethod(impl,padding,@encode(UIEdgeInsets),4);
        if (method) {
            NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (!strcmp([sig getArgumentTypeAtIndex:2],@encode(NSInteger)) && [sig getArgumentTypeAtIndex:3][0]=='@')
                MSHookMessageEx(impl,padding,(IMP)DockPadding,(IMP *)&originalPadding);
        }
        Class controller=NSClassFromString(@"UIInputWindowController");
        SEL scene=NSSelectorFromString(@"_viewSafeAreaInsetsFromScene");
        if (originalPadding && DockMethod(controller,scene,@encode(UIEdgeInsets),2))
            MSHookMessageEx(controller,scene,(IMP)DockSceneInsets,(IMP *)&originalSceneInsets);
        Class dock=NSClassFromString(@"UIKeyboardDockView");
        if (DockMethod(dock,@selector(layoutSubviews),@encode(void),2))
            MSHookMessageEx(dock,@selector(layoutSubviews),(IMP)DockLayout,(IMP *)&originalLayout);
    }
}
