#pragma once
#import <Foundation/Foundation.h>
#define NFBSystemDesktopBundleID @"com.apple.springboard"
static inline BOOL NFBIsSystemDesktop(NSString *app) {
    return [app isKindOfClass:NSString.class] && [app isEqualToString:NFBSystemDesktopBundleID];
}
