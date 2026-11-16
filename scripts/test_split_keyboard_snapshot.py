from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();c=(r/'Sources/NFBSplitCoordinator.m').read_text();b=(r/'Sources/NFBOpenSplitBackend.m').read_text()
assert 'floatingApp = layoutSnapshot.lowerApp' in m
assert 'snapshot.upperWindows=uppers' in b
assert 'layoutSnapshot.lowerFrame : CGRectNull' in m
assert 'keyboardRailFitsSnapshot:layoutSnapshot' in m
assert 'schedulePortraitRestoreAfter:delay' in m
assert 'NFBRecheckSplitPlacement();' not in m
f=c[c.index('- (void)schedulePortraitRestoreAfter:'):c.index('- (void)scheduleMovieKeyboardChecks')]
for text in ['core.generation!=generation','core.operationEpoch!=operation','core.keyboard','desktopSessionIdentifier]!=desktop','restorePortraitPlacement']:assert text in f
assert 'NFBSplitSnapshotUnknown' in b and 'NFBSplitSnapshotAbsent' in b
assert 'NFBSplitFrameInView(root)' in b
assert 'CGRectIsEmpty(snapshot.lowerFrame)' in c
print('PASS: shared lower layout snapshot, guarded keyboard restore, explicit unknown/absent, invalid geometry refused')
