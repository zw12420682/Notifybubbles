#import <UIKit/UIKit.h>
#import "NFBDebugLog.h"
#import <objc/message.h>
#include <string.h>

static inline id NFBEdgeObject(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    @try {
        NSMethodSignature *sig = [object methodSignatureForSelector:sel];
        if (![object respondsToSelector:sel] || !sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(object, sel);
    } @catch (__unused NSException *e) { return nil; }
}
// Read-only inspection. Never invoke a gesture target or synthesize a press.
static inline void NFBInspectEdgeView(UIView *view, NSString *path, NSUInteger depth) {
    if (depth > 4) return;
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        NFBDebugLog(@"EDGE region=%@ view=%@ gesture=%@ enabled=%d", path, NSStringFromClass(view.class), NSStringFromClass(gesture.class), gesture.enabled);
        // Public recognizer metadata only. Private action storage may contain
        // arm64e-authenticated pointers and must not be read or stringified.
    }
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        for (id target in control.allTargets)
            for (NSString *action in [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside])
                NFBDebugLog(@"EDGE control=%@ target=%@ tap=%@", path, NSStringFromClass([target class]), action);
    }
    for (UIView *child in view.subviews) NFBInspectEdgeView(child, [path stringByAppendingString:@"/child"], depth + 1);
}
static inline void NFBInspectTrollEdges(void) {
    static NSHashTable *seen;
    if (!seen) seen = [NSHashTable weakObjectsHashTable];
    id window = NFBEdgeObject(NSClassFromString(@"TOJBBarGestureBridge"), @"currentVisibleFloatingWindow");
    if (!window || [seen containsObject:window]) return;
    BOOL found = NO;
    for (NSString *name in @[@"leftTouchRegion", @"rightTouchRegion", @"bottomTouchRegion", @"topLikeTouchRegions", @"bottomLikeTouchRegions", @"allEdgeTouchRegions"]) {
        id value = NFBEdgeObject(window, name);
        NSArray *views = [value isKindOfClass:UIView.class] ? @[value] :
            ([value isKindOfClass:NSArray.class] ? value : ([value isKindOfClass:NSSet.class] ? [value allObjects] : @[]));
        for (id view in views) if ([view isKindOfClass:UIView.class]) {
            found = YES; NFBInspectEdgeView(view, name, 0);
        }
    }
    if (found) [seen addObject:window];
}
