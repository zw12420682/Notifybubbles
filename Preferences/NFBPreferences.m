#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>

@interface NFBFavoritesController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *apps;
@property(nonatomic, strong) NSMutableArray<NSString *> *selected;
@end

@interface NFBPreferences : PSListController
@end
@implementation NFBPreferences
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSDictionary *symbols = @{@"LandscapeVerticalPosition": @"arrow.up.arrow.down", @"Enabled": @"bell.badge.fill", @"ShowOnLock": @"lock.fill",
            @"ShowOnHome": @"house.fill", @"ShowInApps": @"app.fill", @"IconSize": @"arrow.up.left.and.arrow.down.right",
            @"IconOpacity": @"circle.lefthalf.filled", @"ClosePreviousSplit": @"rectangle.on.rectangle",
            @"FreezeDesktop": @"snowflake", @"DesktopBlurTransparency": @"drop.halffull", @"HideInScreenshots": @"eye.slash.fill"};
        for (PSSpecifier *specifier in _specifiers) {
            NSString *key = [specifier propertyForKey:@"key"];
            NSString *symbol = key ? symbols[key] : nil;
            if ([[specifier propertyForKey:@"action"] isEqual:@"clearBubbles"]) symbol = @"trash.fill";
            if ([[specifier propertyForKey:@"action"] isEqual:@"chooseFavorites"]) symbol = @"star.fill";
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
- (void)chooseFavorites {
    [self.navigationController pushViewController:[[NFBFavoritesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}
- (void)clearBubbles {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("local.notifybubbles/clear"), NULL, NULL, YES);
}
@end

static id NFBPreferenceObject(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (![object respondsToSelector:sel]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, sel); }
    @catch (__unused NSException *e) { return nil; }
}
@implementation NFBFavoritesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"自选常用 App";
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    id stored = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("FavoriteApps"), CFSTR("local.notifybubbles")));
    self.selected = [NSMutableArray array];
    if ([stored isKindOfClass:NSArray.class]) for (id app in stored)
        if ([app isKindOfClass:NSString.class] && ![self.selected containsObject:app]) [self.selected addObject:app];
    id workspace = NFBPreferenceObject(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    id installed = NFBPreferenceObject(workspace, @"allInstalledApplications");
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    if ([installed isKindOfClass:NSArray.class]) for (id proxy in installed) {
        id app = NFBPreferenceObject(proxy, @"applicationIdentifier");
        id name = NFBPreferenceObject(proxy, @"localizedName");
        if (![app isKindOfClass:NSString.class] || ![app length] || [app isEqual:@"com.apple.springboard"]) continue;
        if (![name isKindOfClass:NSString.class] || ![name length]) continue;
        byID[app] = @{@"id": app, @"name": name};
    }
    // Preserve saved choices even when an app was removed, so it can be deselected.
    for (NSString *app in self.selected) if (!byID[app]) byID[app] = @{@"id": app, @"name": app};
    self.apps = [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return self.apps.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.apps.count ? @"点选后即时保存，初始按选择顺序排列，当前 App 不改变排序，只滚动到可见位置。上方常用容器最多显示 4 个，其余可滚动查看；从下往上排列，最下面为第一位；已选 App 不再显示在下方容器。" : @"未能读取已安装 App，请重新打开设置并确认插件正常加载。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *app = self.apps[indexPath.row];
    cell.textLabel.text = app[@"name"]; cell.detailTextLabel.text = app[@"id"];
    cell.accessoryType = [self.selected containsObject:app[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.imageView.image = [UIImage systemImageNamed:@"app.fill"];
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImage respondsToSelector:sel]) {
        @try { cell.imageView.image = ((id (*)(id, SEL, id, int, CGFloat))objc_msgSend)(UIImage.class, sel, app[@"id"], 0, UIScreen.mainScreen.scale) ?: cell.imageView.image; }
        @catch (__unused NSException *e) {}
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *app = self.apps[indexPath.row][@"id"];
    if ([self.selected containsObject:app]) [self.selected removeObject:app]; else [self.selected addObject:app];
    CFPreferencesSetAppValue(CFSTR("FavoriteApps"), (__bridge CFPropertyListRef)self.selected, CFSTR("local.notifybubbles"));
    CFPreferencesAppSynchronize(CFSTR("local.notifybubbles"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("local.notifybubbles/preferences.changed"), NULL, NULL, YES);
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}
@end
