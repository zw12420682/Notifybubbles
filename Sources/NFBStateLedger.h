#pragma once
#import <Foundation/Foundation.h>

// First value wins per object/property. Restore in reverse order, independently.
@interface NFBStateLedger : NSObject
- (void)remember:(id)object key:(NSString *)key restore:(void (^)(void))restore;
- (void)restore;
@end
void NFBAttemptCleanup(NSString *stage, void (^cleanup)(void));
