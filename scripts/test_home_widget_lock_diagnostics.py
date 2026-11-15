from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'Sources/NFBDesktopHost.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
f=h[h.index('static void NFBLogLockHomeWidgets('):h.index('void NFBObserveHomeWidgetLockDiagnostics(')]
for forbidden in ('setContentOffset','snapshotViewAfterScreenUpdates','refreshWidgetPage','addSubview','addGestureRecognizer','NFBUpdateMovieMode','NFBSingleton'):
 assert forbidden not in f,forbidden
assert 'NFBLogWidgetHosts(root,0,&budget)' in f
assert "NFBLogLockHomeWidgets(\"unlock\")" in h
assert '0.6*NSEC_PER_SEC' in h
assert 'NFBObserveHomeWidgetLockDiagnostics([self isLocked], self.enabled)' in m
assert 'NFBObserveHomeWidgetLock(' not in m
assert 'homeRecovery' not in h
print('PASS: lock/unlock snapshot is read-only; no refresh, page move, gesture or overlay')
