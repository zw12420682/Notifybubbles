#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>

@interface NFBPreferences : PSListController
@end
@implementation NFBPreferences
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSDictionary *symbols = @{@"Enabled": @"bell.badge.fill", @"ShowOnLock": @"lock.fill",
            @"ShowOnHome": @"house.fill", @"ShowInApps": @"app.fill", @"IconSize": @"arrow.up.left.and.arrow.down.right",
            @"IconOpacity": @"circle.lefthalf.filled", @"ClosePreviousSplit": @"rectangle.on.rectangle",
            @"FreezeDesktop": @"snowflake", @"HideInScreenshots": @"eye.slash.fill"};
        for (PSSpecifier *specifier in _specifiers) {
            NSString *key = [specifier propertyForKey:@"key"];
            NSString *symbol = key ? symbols[key] : nil;
            if ([[specifier propertyForKey:@"action"] isEqual:@"clearBubbles"]) symbol = @"trash.fill";
            if (!symbol) continue;
            UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:
                [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
            image = [image imageWithTintColor:UIColor.systemBlueColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (image) [specifier setProperty:image forKey:@"iconImage"];
        }
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
