#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "NFBKeyboardDockPolicy.h"
#import "NFBKeyboardSettingsBridge.h"
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <stdarg.h>

// Bounded diagnostics for loading/configuration/first calls only. Never log
// typed text, input mode contents, key events or clipboard data.
static void DockLog(NSString *format,...) NS_FORMAT_FUNCTION(1,2);
static void DockLog(NSString *format,...) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("local.notifybubbles.keyboard-diagnostics",DISPATCH_QUEUE_SERIAL); });
    va_list args; va_start(args,format);
    NSString *message=[[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    dispatch_async(queue, ^{
        @autoreleasepool {
            static NSUInteger count;
            if (count++>=128) return;
            static NSString *path;
            static BOOL selected;
            if (!selected) {
                selected=YES;
                NSString *filename=[NSString stringWithFormat:@"nfb-keyboard-%d.log",getpid()];
                for (NSString *candidate in @[[ @"/var/tmp" stringByAppendingPathComponent:filename],
                    [NSTemporaryDirectory() stringByAppendingPathComponent:filename]]) {
                    FILE *probe=fopen(candidate.fileSystemRepresentation,"a");
                    if (probe) { fclose(probe); path=candidate; break; }
                }
                NSLog(@"[NFB keyboard] diagnostics path=%@",path ?: @"unavailable");
            }
            NSString *line=[NSString stringWithFormat:@"%@ pid=%d process=%@ bundle=%@ %@\n",NSDate.date,getpid(),
                NSProcessInfo.processInfo.processName,NSBundle.mainBundle.bundleIdentifier ?: @"none",message];
            NSLog(@"[NFB keyboard] %@",message);
            if (!path) return;
            FILE *file=fopen(path.fileSystemRepresentation,"a");
            if (!file) return;
            if (!fseek(file,0,SEEK_END) && ftell(file)<262144) fputs(line.UTF8String,file);
            fclose(file);
        }
    });
}

static BOOL customHeight, hideGlobe, hideVoice;
static double requestedHeight=34;
static BOOL DockSettingsPublisher(void) {
    NSString *bundle=NSBundle.mainBundle.bundleIdentifier;
    return [bundle isEqualToString:@"com.apple.springboard"] || [bundle isEqualToString:@"com.apple.Preferences"];
}
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
    BOOL publisher=DockSettingsPublisher();
    BOOL published=publisher ? NFBKeyboardSettingsPublish() : NO;
    NFBKeyboardSettings received={0,0,0,34};
    BOOL shared=!publisher && NFBKeyboardSettingsReceive(&received);
    if (shared) {
        customHeight=received.enabled; requestedHeight=received.height;
        hideGlobe=received.globe; hideVoice=received.voice;
    }
    DockLog(@"config source=%@ published=%d presence height=%d enabled=%d globe=%d voice=%d | decoded custom=%d height=%.2f globe=%d voice=%d threadMain=%d",
        shared ? @"notify-state" : @"preferences",published,height!=nil,enabled!=nil,globe!=nil,voice!=nil,
        customHeight,requestedHeight,hideGlobe,hideVoice,NSThread.isMainThread);
}
static void DockChanged(__unused CFNotificationCenterRef center,__unused void *observer,__unused CFStringRef name,__unused const void *object,__unused CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ DockLoad(); });
}
static UIEdgeInsets (*originalPadding)(id,SEL,NSInteger,id);
static UIEdgeInsets DockPadding(id object,SEL selector,NSInteger orientation,id mode) {
    UIEdgeInsets insets=originalPadding(object,selector,orientation,mode);
    CGFloat systemBottom=insets.bottom;
    insets.bottom=NFBKeyboardDockBottom(insets.bottom,customHeight,requestedHeight,orientation==1 || orientation==2);
    static NSUInteger reports;
    if (reports++<3) DockLog(@"padding called orientation=%ld system=%.2f result=%.2f custom=%d",(long)orientation,(double)systemBottom,(double)insets.bottom,customHeight);
    return insets;
}
static UIEdgeInsets (*originalSceneInsets)(id,SEL);
static UIEdgeInsets DockSceneInsets(id object,SEL selector) {
    UIEdgeInsets insets=originalSceneInsets(object,selector);
    CGSize size=UIScreen.mainScreen.bounds.size;
    CGFloat systemBottom=insets.bottom;
    insets.bottom=NFBKeyboardDockBottom(insets.bottom,customHeight,requestedHeight,size.height>size.width);
    static NSUInteger reports;
    if (reports++<3) DockLog(@"scene-insets called portrait=%d system=%.2f result=%.2f",size.height>size.width,(double)systemBottom,(double)insets.bottom);
    return insets;
}
static void DockHideItem(UIView *dock,NSString *getter,BOOL hide) {
    if (!hide) return;
    id item=DockObject(dock,getter);
    id button=DockObject(item,@"button");
    static NSUInteger reports;
    if (reports++<6) DockLog(@"dock item=%@ itemClass=%@ buttonClass=%@ descendant=%d",getter,NSStringFromClass([item class]),NSStringFromClass([button class]),
        [button isKindOfClass:UIView.class] && [(UIView *)button isDescendantOfView:dock]);
    if (![button isKindOfClass:UIView.class] || ![(UIView *)button isDescendantOfView:dock]) return;
    if (![hiddenButtons objectForKey:button]) [hiddenButtons setObject:@([(UIView *)button isHidden]) forKey:button];
    [(UIView *)button setHidden:YES];
}
static void (*originalLayout)(UIView *,SEL);
static void DockLayout(UIView *dock,SEL selector) {
    originalLayout(dock,selector);
    static NSUInteger reports;
    if (reports++<3) DockLog(@"dock-layout called class=%@ globe=%d voice=%d",NSStringFromClass(dock.class),hideGlobe,hideVoice);
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
        DockLog(@"module loaded version=0.48.55 idiom=%ld",(long)UIDevice.currentDevice.userInterfaceIdiom);
        // A separate UIKit filter; no manager, window scans or timers in apps.
        if (UIDevice.currentDevice.userInterfaceIdiom!=UIUserInterfaceIdiomPhone) return;
        hiddenButtons=[NSMapTable weakToStrongObjectsMapTable];
        static int settingsObserver=-1;
        uint32_t registration=notify_register_dispatch(NFB_KEYBOARD_SETTINGS_CHANNEL,&settingsObserver,dispatch_get_main_queue(),^(__unused int token) {
            if (!DockSettingsPublisher()) DockLoad();
        });
        DockLog(@"settings notification registration=%u",registration);
        DockLoad();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,DockChanged,
            CFSTR("local.notifybubbles/preferences.changed"),NULL,CFNotificationSuspensionBehaviorCoalesce);
        Class impl=object_getClass(NSClassFromString(@"UIKeyboardImpl"));
        SEL padding=NSSelectorFromString(@"deviceSpecificPaddingForInterfaceOrientation:inputMode:");
        Method method=DockMethod(impl,padding,@encode(UIEdgeInsets),4);
        Method actual=class_getInstanceMethod(impl,padding);
        DockLog(@"padding interface class=%d method=%d encoding=%s",impl!=Nil,actual!=NULL,actual ? method_getTypeEncoding(actual) : "missing");
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
        DockLog(@"hooks installed padding=%d scene=%d dock=%d",originalPadding!=NULL,originalSceneInsets!=NULL,originalLayout!=NULL);
    }
}
