#import "NFBStateLedger.h"
#import "NFBDebugLog.h"

@interface NFBSavedState : NSObject
@property(nonatomic,copy) NSString *key;
@property(nonatomic,copy) void (^restoreValue)(void);
@end
@implementation NFBSavedState @end

@interface NFBStateLedger ()
@property(nonatomic,strong) NSMapTable<id, NSMutableSet<NSString *> *> *keys;
@property(nonatomic,strong) NSMutableArray<NFBSavedState *> *entries;
@end
@implementation NFBStateLedger
- (instancetype)init {
    if ((self=[super init])) {
        _keys=[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                  valueOptions:NSPointerFunctionsStrongMemory];
        _entries=[NSMutableArray array];
    }
    return self;
}
- (void)remember:(id)object key:(NSString *)key restore:(void (^)(void))restore {
    if (!object || !key.length || !restore) return;
    NSMutableSet *seen=[self.keys objectForKey:object];
    if ([seen containsObject:key]) return;
    if (!seen) { seen=[NSMutableSet set]; [self.keys setObject:seen forKey:object]; }
    [seen addObject:key];
    NFBSavedState *entry=[NFBSavedState new]; entry.key=key; entry.restoreValue=restore;
    [self.entries addObject:entry];
}
- (void)restore {
    NSArray *entries=[self.entries copy];
    [self.entries removeAllObjects]; [self.keys removeAllObjects];
    for (NFBSavedState *entry in entries.reverseObjectEnumerator)
        NFBAttemptCleanup(entry.key,entry.restoreValue);
}
@end
void NFBAttemptCleanup(NSString *stage, void (^cleanup)(void)) {
    @try { if (cleanup) cleanup(); }
    @catch (NSException *error) { NFBErrorLog(@"cleanup %@ failed: %@",stage,error); }
}
