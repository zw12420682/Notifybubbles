from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBDesktopHost.m').read_text()
a=s.index('@interface NFBWidgetWatch');b=s.index('// An open request is not success',a);f=s[a:b]
assert '@property(nonatomic,weak) UIView *view' in f
assert 'visited<4096' in f and 'depth>=40' in f
assert 'pending=%lu depthLimitHits=%lu' in f
assert 'alive=%d parent=%p originalParent=%@' in f
assert 'epoch!=current || previous' in f
assert 'widgetWatches.count>=96' in f
assert 'NFBWidgetWatchSample("lock-edge")' in f
for forbidden in ['setContentOffset:', 'snapshotViewAfterScreenUpdates:', 'layoutIfNeeded', 'beginAppearanceTransition:', 'addGestureRecognizer:', 'addSubview:']:
 assert forbidden not in f,forbidden
assert 'isViewLoaded' in f
print('PASS: weak bounded identity tracking, explicit scan completeness, epoch-bound samples, no widget/page/input mutation')
