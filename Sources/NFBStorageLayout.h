#import <Foundation/Foundation.h>
// Logical rows, bottom first. Hidden apps have no individual layout slots.
static inline NSMutableArray<NSString *> *NFBFoldedRowsKeeping(NSArray<NSString *> *apps, NSString *storageID, NSSet<NSString *> *keep,
    NSUInteger (^unreadCount)(NSString *), NSUInteger *storedCount) {
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger hidden = 0;
    for (NSString *app in apps) {
        if ([keep containsObject:app] || unreadCount(app) > 0) [rows addObject:app];
        else hidden++;
    }
    if (hidden) [rows insertObject:storageID atIndex:0];
    if (storedCount) *storedCount = hidden;
    return rows;
}

static inline NSMutableArray<NSString *> *NFBFoldedRows(NSArray<NSString *> *apps, NSString *storageID,
    NSUInteger (^unreadCount)(NSString *), NSUInteger *storedCount) {
    return NFBFoldedRowsKeeping(apps, storageID, nil, unreadCount, storedCount);
}
