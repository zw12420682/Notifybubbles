#import "OSSettings.h"
#import <notify.h>

NSString * const kOSSettingsChangedNotification = @"com.ownsplit.tweak/settings.changed";

static NSString * const kPrefsDomain = @"com.ownsplit.tweak";

static NSString *OSPreferencesPath(void) {
    return @"/var/mobile/Library/Preferences/com.ownsplit.tweak.plist";
}

@interface OSSettings ()
@property (nonatomic, strong) NSDictionary *raw;
@end

@implementation OSSettings {
    int _token;
}

+ (instancetype)shared {
    static OSSettings *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OSSettings alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reload];
        __weak typeof(self) weakSelf = self;
        notify_register_dispatch("com.ownsplit.tweak/settings.changed",
                                 &_token,
                                 dispatch_get_main_queue(),
                                 ^(int token) {
            (void)token;
            [weakSelf reload];
            [[NSNotificationCenter defaultCenter] postNotificationName:kOSSettingsChangedNotification
                                                                object:weakSelf];
        });
    }
    return self;
}

- (void)reload {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // CFPreferences first (works with PreferenceLoader)
    CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)kPrefsDomain,
                                               kCFPreferencesCurrentUser,
                                               kCFPreferencesAnyHost);
    if (keys) {
        CFDictionaryRef values = CFPreferencesCopyMultiple(keys,
                                                           (__bridge CFStringRef)kPrefsDomain,
                                                           kCFPreferencesCurrentUser,
                                                           kCFPreferencesAnyHost);
        if (values) {
            [dict addEntriesFromDictionary:(__bridge NSDictionary *)values];
            CFRelease(values);
        }
        CFRelease(keys);
    }

    // CFPreferences is preferred; this fallback uses the rootless bootstrap path.
    if (dict.count == 0) {
        NSDictionary *fileDict = [NSDictionary dictionaryWithContentsOfFile:OSPreferencesPath()];
        if (fileDict) {
            [dict addEntriesFromDictionary:fileDict];
        }
    }

    self.raw = [dict copy];
}

- (id)objectForKey:(NSString *)key default:(id)fallback {
    id value = self.raw[key];
    return value ?: fallback;
}

- (BOOL)boolForKey:(NSString *)key default:(BOOL)fallback {
    id value = self.raw[key];
    if (!value) return fallback;
    return [value boolValue];
}

- (CGFloat)floatForKey:(NSString *)key default:(CGFloat)fallback {
    id value = self.raw[key];
    if (!value) return fallback;
    return [value doubleValue];
}

- (NSInteger)integerForKey:(NSString *)key default:(NSInteger)fallback {
    id value = self.raw[key];
    if (!value) return fallback;
    return [value integerValue];
}

#pragma mark - Public accessors

- (BOOL)isEnabled {
    return [self boolForKey:@"enabled" default:YES];
}

- (CGFloat)floatingOpacity {
    CGFloat o = [self floatForKey:@"floatingOpacity" default:1.0];
    return MIN(1.0, MAX(0.5, o));
}

- (CGFloat)floatingCornerRadius {
    return [self floatForKey:@"floatingCornerRadius" default:16.0];
}

- (CGSize)defaultFloatingSize {
    CGFloat w = [self floatForKey:@"floatingWidth" default:280.0];
    CGFloat h = [self floatForKey:@"floatingHeight" default:500.0];
    return CGSizeMake(MAX(180, w), MAX(220, h));
}

- (BOOL)showBorder {
    return [self boolForKey:@"showBorder" default:YES];
}

- (BOOL)hapticFeedback {
    return [self boolForKey:@"hapticFeedback" default:YES];
}

- (BOOL)rememberLastApps {
    return [self boolForKey:@"rememberLastApps" default:YES];
}

- (BOOL)allowLandscape {
    return [self boolForKey:@"allowLandscape" default:YES];
}

- (NSInteger)maxFloatingWindows {
    NSInteger n = [self integerForKey:@"maxFloatingWindows" default:2];
    return MIN(4, MAX(1, n));
}

- (NSArray<NSNumber *> *)enabledGestures {
    NSArray *arr = self.raw[@"enabledGestures"];
    if ([arr isKindOfClass:[NSArray class]] && arr.count > 0) {
        return arr;
    }
    // 根据设置页的独立开关重建（图标触发默认开启，更容易用）
    NSMutableArray *built = [NSMutableArray array];
    if ([self boolForKey:@"gestureEdgeSwipe" default:NO]) {
        [built addObject:@(OSActivationGestureEdgeSwipe)];
    }
    if ([self boolForKey:@"gestureThreeFinger" default:NO]) {
        [built addObject:@(OSActivationGestureThreeFingerSwipeUp)];
    }
    if ([self boolForKey:@"gestureStatusBar" default:NO]) {
        [built addObject:@(OSActivationGestureStatusBarDoubleTap)];
    }
    if ([self boolForKey:@"gestureHomeIndicator" default:NO]) {
        [built addObject:@(OSActivationGestureHomeIndicatorLongPress)];
    }
    if ([self boolForKey:@"gestureIconSwipeUp" default:YES]) {
        [built addObject:@(OSActivationGestureIconSwipeUp)];
    }
    if ([self boolForKey:@"gestureIconLongPress" default:YES]) {
        [built addObject:@(OSActivationGestureIconLongPress)];
    }
    if (built.count > 0) return [built copy];
    // 兜底：图标上滑 + 图标长按
    return @[@(OSActivationGestureIconSwipeUp),
             @(OSActivationGestureIconLongPress)];
}

- (NSArray<NSString *> *)blacklist {
    NSArray *arr = self.raw[@"blacklist"];
    return [arr isKindOfClass:[NSArray class]] ? arr : @[];
}

- (NSArray<NSString *> *)favorites {
    NSArray *arr = self.raw[@"favorites"];
    return [arr isKindOfClass:[NSArray class]] ? arr : @[];
}

- (CGFloat)edgeSwipeSensitivity {
    CGFloat s = [self floatForKey:@"edgeSwipeSensitivity" default:0.5];
    return MIN(1.0, MAX(0.0, s));
}

- (BOOL)animateTransitions {
    return [self boolForKey:@"animateTransitions" default:YES];
}

- (CGRect)lastFloatingFrame {
    NSDictionary *d = self.raw[@"lastFloatingFrame"];
    if (![d isKindOfClass:[NSDictionary class]]) return CGRectNull;
    return CGRectMake([d[@"x"] doubleValue],
                      [d[@"y"] doubleValue],
                      [d[@"w"] doubleValue],
                      [d[@"h"] doubleValue]);
}

#pragma mark - Mutators (write back)

- (void)writeValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);

    NSMutableDictionary *m = [self.raw mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) m[key] = value;
    else [m removeObjectForKey:key];
    self.raw = [m copy];
}

- (void)setLastFloatingFrame:(CGRect)frame {
    if (CGRectIsNull(frame) || CGRectIsEmpty(frame)) return;
    NSDictionary *d = @{
        @"x": @(frame.origin.x),
        @"y": @(frame.origin.y),
        @"w": @(frame.size.width),
        @"h": @(frame.size.height),
    };
    [self writeValue:d forKey:@"lastFloatingFrame"];
}

- (CGFloat)lastSplitRatio { CGFloat r=[self floatForKey:@"lastSplitRatio" default:0.5]; return MIN(0.72,MAX(0.28,r)); }
- (NSString *)lastPrimaryBundleID { return [self.raw[@"lastPrimaryBundleID"] isKindOfClass:[NSString class]] ? self.raw[@"lastPrimaryBundleID"] : @"com.apple.springboard"; }
- (NSString *)lastSecondaryBundleID { return [self.raw[@"lastSecondaryBundleID"] isKindOfClass:[NSString class]] ? self.raw[@"lastSecondaryBundleID"] : @""; }
- (void)setLastSplitRatio:(CGFloat)ratio { [self writeValue:@(MIN(0.72,MAX(0.28,ratio))) forKey:@"lastSplitRatio"]; }
- (void)setLastPrimaryBundleID:(NSString *)bundleID { if(bundleID.length)[self writeValue:bundleID forKey:@"lastPrimaryBundleID"]; }
- (void)setLastSecondaryBundleID:(NSString *)bundleID { if(bundleID.length)[self writeValue:bundleID forKey:@"lastSecondaryBundleID"]; }

- (BOOL)isBundleBlacklisted:(NSString *)bundleID {
    if (!bundleID) return YES;
    return [self.blacklist containsObject:bundleID];
}

- (BOOL)isGestureEnabled:(OSActivationGesture)gesture {
    return [self.enabledGestures containsObject:@(gesture)];
}

@end
