#import "NFBWidgetDetachTrace.h"
#import "NFBDebugLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#ifndef NFB_DESKTOP_SIM_TEST
#import <substrate.h>
#endif
static NSUInteger nfbDetachBudget;
static BOOL nfbDetachArmed;
static BOOL nfbViewInstalled, nfbWillInstalled, nfbDidInstalled, nfbRemoveInstalled;
static void (*nfbOriginalViewMove)(id,SEL);
static void (*nfbOriginalWillParent)(id,SEL,id);
static void (*nfbOriginalDidParent)(id,SEL,id);
static void (*nfbOriginalRemoveParent)(id,SEL);
static BOOL NFBWidgetController(id object) {
    return [object isKindOfClass:NSClassFromString(@"SBHWidgetViewController")];
}
static void NFBWidgetDetachStack(id object, NSString *event) {
    if (!NFBDebugLoggingEnabled() || !nfbDetachBudget) return;
    nfbDetachBudget--;
    @try {
        NSArray *stack=NSThread.callStackSymbols;
        NSUInteger count=MIN(stack.count,(NSUInteger)22);
        // Split stacks into short records so the logger's per-line cap cannot
        // discard the actual caller. Object address matches widget-watch logs.
        NFBDebugLog(@"widget-detach: event=%@ object=%p class=%@ frames=%lu remaining=%lu",
            event,object,NSStringFromClass([object class]),(unsigned long)count,(unsigned long)nfbDetachBudget);
        for (NSUInteger i=0;i<count;i+=4) {
            NSArray *part=[stack subarrayWithRange:NSMakeRange(i,MIN((NSUInteger)4,count-i))];
            NFBDebugLog(@"widget-detach-stack: object=%p event=%@ offset=%lu %@",object,event,(unsigned long)i,
                [part componentsJoinedByString:@" <- "]);
        }
    } @catch (__unused NSException *error) {}
}
static void NFBWidgetViewMoved(id object,SEL selector) {
    nfbOriginalViewMove(object,selector);
    if (!NFBDebugLoggingEnabled() || !NSThread.isMainThread || !nfbDetachBudget) return;
    UIView *view=object;
    NFBWidgetDetachStack(object,[NSString stringWithFormat:@"didMove parent=%p window=%p",view.superview,view.window]);
}
static void NFBWidgetWillParent(id object,SEL selector,id parent) {
    if (NFBDebugLoggingEnabled() && NSThread.isMainThread && nfbDetachBudget && NFBWidgetController(object)) NFBWidgetDetachStack(object,[NSString stringWithFormat:@"willMove parent=%p",parent]);
    nfbOriginalWillParent(object,selector,parent);
}
static void NFBWidgetDidParent(id object,SEL selector,id parent) {
    nfbOriginalDidParent(object,selector,parent);
    if (NFBDebugLoggingEnabled() && NSThread.isMainThread && nfbDetachBudget && NFBWidgetController(object)) NFBWidgetDetachStack(object,[NSString stringWithFormat:@"didMove parent=%p",parent]);
}
static void NFBWidgetRemoveParent(id object,SEL selector) {
    if (NFBDebugLoggingEnabled() && NSThread.isMainThread && nfbDetachBudget && NFBWidgetController(object)) NFBWidgetDetachStack(object,@"removeFromParent");
    nfbOriginalRemoveParent(object,selector);
}
#ifndef NFB_DESKTOP_SIM_TEST
static BOOL NFBInstallWidgetTrace(Class cls, SEL selector, IMP replacement, IMP *original, BOOL objectArgument) {
    if (!cls) return NO;
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return NO;
    NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!sig || strcmp(sig.methodReturnType,@encode(void)) || sig.numberOfArguments!=(objectArgument?3:2) ||
        (objectArgument && [sig getArgumentTypeAtIndex:2][0]!='@')) {
        NFBDebugLog(@"widget-detach: rejected signature class=%@ selector=%@ encoding=%s",NSStringFromClass(cls),NSStringFromSelector(selector),method_getTypeEncoding(method));
        return NO;
    }
    // Install on the target class, not its superclass if the method is inherited.
    // This avoids changing unrelated UIView/UIViewController dispatch.
    class_addMethod(cls,selector,method_getImplementation(method),method_getTypeEncoding(method));
    MSHookMessageEx(cls,selector,replacement,original);
    NFBDebugLog(@"widget-detach: installed class=%@ selector=%@ encoding=%s",NSStringFromClass(cls),NSStringFromSelector(selector),method_getTypeEncoding(method));
    return *original!=NULL;
}
#endif
void NFBArmWidgetDetachTrace(BOOL newLockCycle) {
    if (!NSThread.isMainThread || !NFBDebugLoggingEnabled()) return;
    if (newLockCycle || !nfbDetachArmed) { nfbDetachBudget=48; nfbDetachArmed=YES; }
#ifndef NFB_DESKTOP_SIM_TEST
    Class view=NSClassFromString(@"CHUISWidgetHostViewControllerView");
    Class controller=NSClassFromString(@"SBHWidgetViewController");
    if (!nfbViewInstalled) nfbViewInstalled=NFBInstallWidgetTrace(view,@selector(didMoveToSuperview),(IMP)NFBWidgetViewMoved,(IMP *)&nfbOriginalViewMove,NO);
    if (!nfbWillInstalled) nfbWillInstalled=NFBInstallWidgetTrace(controller,@selector(willMoveToParentViewController:),(IMP)NFBWidgetWillParent,(IMP *)&nfbOriginalWillParent,YES);
    if (!nfbDidInstalled) nfbDidInstalled=NFBInstallWidgetTrace(controller,@selector(didMoveToParentViewController:),(IMP)NFBWidgetDidParent,(IMP *)&nfbOriginalDidParent,YES);
    if (!nfbRemoveInstalled) nfbRemoveInstalled=NFBInstallWidgetTrace(controller,@selector(removeFromParentViewController),(IMP)NFBWidgetRemoveParent,(IMP *)&nfbOriginalRemoveParent,NO);
#endif
}
