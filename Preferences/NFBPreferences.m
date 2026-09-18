#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface NFBPreferences : PSListController
@end
@implementation NFBPreferences
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
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
