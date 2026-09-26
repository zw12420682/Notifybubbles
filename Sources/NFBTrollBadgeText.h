#import <Foundation/Foundation.h>
static inline NSString *NFBTrollBadgeText(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [value doubleValue] > 0 ? [value stringValue] : nil;
    if ([value isKindOfClass:NSString.class] && [value length] && ![value isEqual:@"0"]) return value;
    return nil;
}
