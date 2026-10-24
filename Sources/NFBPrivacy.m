#import "NFBPrivacy.h"
#import "NFBDebugLog.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

void NFBSetCaptureHidden(UIView *view, BOOL hidden) {
    if (!view) return;
    CALayer *layer = view.layer;
    static char savedMaskKey;
    NSString *key = @"disableUpdateMask";
    if (![layer respondsToSelector:NSSelectorFromString(key)] ||
        ![layer respondsToSelector:NSSelectorFromString(@"setDisableUpdateMask:")]) return;
    @try {
        NSNumber *saved = objc_getAssociatedObject(layer, &savedMaskKey);
        if (hidden) {
            if (!saved) {
                saved = [layer valueForKey:key];
                objc_setAssociatedObject(layer, &savedMaskKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            NSNumber *current = [layer valueForKey:key];
            unsigned int target = current.unsignedIntValue | 0x12;
            if (current.unsignedIntValue != target) [layer setValue:@(target) forKey:key];
        } else if (saved) {
            NSNumber *current = [layer valueForKey:key];
            unsigned int restored = (current.unsignedIntValue & ~0x12u) | (saved.unsignedIntValue & 0x12u);
            if (current.unsignedIntValue != restored) [layer setValue:@(restored) forKey:key];
            objc_setAssociatedObject(layer, &savedMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *exception) { NFBErrorLog(@"capture hiding unavailable: %@", exception); }
}
