#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>

@interface NFBPreferences : PSListController
@end
@interface NFBAppPreferences : NFBPreferences
@end

@implementation NFBPreferences
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:@"各 App 新消息图标" target:self
            set:NULL get:NULL detail:NFBAppPreferences.class cell:PSLinkCell edit:Nil];
        [items addObject:link];
        _specifiers = items;
    }
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)[specifier propertyForKey:@"key"], CFSTR("local.notifybubbles")));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"],
        (__bridge CFPropertyListRef)value, CFSTR("local.notifybubbles"));
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("local.notifybubbles/preferences.changed"), NULL, NULL, YES);
}
- (void)clearBubbles {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("local.notifybubbles/clear"), NULL, NULL, YES);
}
@end

static id NFBAppProperty(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    @try {
        NSMethodSignature *sig = [object methodSignatureForSelector:sel];
        if (![object respondsToSelector:sel] || !sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(object, sel);
    } @catch (__unused NSException *e) { return nil; }
}
@implementation NFBAppPreferences
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"各 App 新消息图标"];
    [group setProperty:@"默认开启。关闭仅隐藏通知来源的图标，不影响切换器中的 App 图标，也不关闭系统通知。" forKey:@"footerText"];
    [items addObject:group];
    id workspace = NFBAppProperty(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    id proxies = NFBAppProperty(workspace, @"allInstalledApplications");
    if (![proxies isKindOfClass:NSArray.class]) proxies = NFBAppProperty(workspace, @"allApplications");
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    if ([proxies isKindOfClass:NSArray.class]) for (id proxy in proxies) {
        id app = NFBAppProperty(proxy, @"bundleIdentifier") ?: NFBAppProperty(proxy, @"applicationIdentifier");
        id name = NFBAppProperty(proxy, @"localizedName");
        if (![app isKindOfClass:NSString.class] || ![app length] || [app isEqual:@"com.apple.springboard"]) continue;
        names[app] = [name isKindOfClass:NSString.class] && [name length] ? name : app;
    }
    NSArray *apps = [names.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [names[a] localizedStandardCompare:names[b]];
    }];
    for (NSString *app in apps) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:names[app] target:self
            set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
            detail:Nil cell:PSSwitchCell edit:Nil];
        [item setProperty:[@"NotifyApp." stringByAppendingString:app] forKey:@"key"];
        [item setProperty:@YES forKey:@"default"];
        [items addObject:item];
    }
    if (!apps.count) {
        PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:@"暂时无法读取应用列表"];
        [empty setProperty:@"请重新打开设置；若仍为空，请反馈以适配当前环境。" forKey:@"footerText"];
        [items addObject:empty];
    }
    _specifiers = items;
    return _specifiers;
}
@end
