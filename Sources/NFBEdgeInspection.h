#import <UIKit/UIKit.h>
#import "NFBDebugLog.h"
#import <objc/message.h>
#include <string.h>
#include <stdlib.h>

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
        @try {
            id targets = [gesture valueForKey:@"_targets"];
            NFBDebugLog(@"EDGE2 gestureDescription=%@", gesture.description);
            NFBDebugLog(@"EDGE2 targetsClass=%@ targets=%@", NSStringFromClass([targets class]), targets);
            NSArray *entries = [targets isKindOfClass:NSArray.class] ? targets :
                ([targets isKindOfClass:NSSet.class] ? [targets allObjects] : @[]);
            if ([targets isKindOfClass:NSOrderedSet.class]) entries = [targets array];
            for (id entry in entries) {
                NFBDebugLog(@"EDGE2 entryClass=%@ description=%@", NSStringFromClass([entry class]), entry);
                // Report actual ivar names/types instead of silently requiring one layout.
                for (Class cls = [entry class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
                    unsigned int count = 0;
                    Ivar *vars = class_copyIvarList(cls, &count);
                    for (unsigned int i = 0; i < count; i++)
                        NFBDebugLog(@"EDGE2 ivar=%s type=%s", ivar_getName(vars[i]), ivar_getTypeEncoding(vars[i]));
                    free(vars);
                }
                Ivar targetVar = class_getInstanceVariable([entry class], "_target");
                Ivar actionVar = class_getInstanceVariable([entry class], "_action");
                if (!targetVar || !actionVar || ivar_getTypeEncoding(targetVar)[0] != '@' || strcmp(ivar_getTypeEncoding(actionVar), ":") != 0) continue;
                id target = object_getIvar(entry, targetVar);
                SEL action = NULL;
                ptrdiff_t offset = ivar_getOffset(actionVar);
                if (offset < 0 || (size_t)offset + sizeof(action) > class_getInstanceSize([entry class])) continue;
                memcpy(&action, (const char *)(__bridge const void *)entry + offset, sizeof(action));
                if (!action || ![target respondsToSelector:action]) continue;
                Method method = class_getInstanceMethod(object_getClass(target), action);
                NFBDebugLog(@"EDGE target=%@ action=%@ encoding=%s", NSStringFromClass([target class]), NSStringFromSelector(action), method ? method_getTypeEncoding(method) : "unknown");
            }
        } @catch (__unused NSException *e) { NFBDebugLog(@"EDGE target inspection unavailable for %@", path); }
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
