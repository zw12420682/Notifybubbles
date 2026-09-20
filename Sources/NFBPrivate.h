#import <UIKit/UIKit.h>
#import <objc/message.h>

// Minimal declarations, resolved at runtime; no private class is linked directly.
@interface NSObject (NFBPrivate)
- (id)delegate;
- (NSString *)sectionIdentifier;
- (NSString *)notificationIdentifier;
- (id)defaultAction;
- (id)content;
- (UIImage *)icon;
- (NSSet *)requestDestinations;
- (NSString *)identifier;
- (BOOL)isUILocked;
- (BOOL)isShowingHomescreen;
- (id)model;
- (id)applicationIconForBundleIdentifier:(NSString *)identifier;
- (id)badgeNumberOrString;
- (void)destination:(id)destination executeAction:(id)action
    forNotificationRequest:(id)request requestAuthentication:(BOOL)authenticate
    withParameters:(NSDictionary *)parameters completion:(id)completion;
@end

static inline id NFBGet(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *error) { return nil; }
}
static inline id NFBSingleton(NSString *className) {
    return NFBGet(NSClassFromString(className), @"sharedInstance");
}
static inline NSString *NFBString(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}
