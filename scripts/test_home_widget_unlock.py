from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBDesktopHost.m').read_text()
a=s.index('@interface NFBHomeWidgetRecovery');b=s.index('BOOL NFBShowDesktopInSplit(',a);f=s[a:b]
assert 'previous && !locked' in f
assert 'NFBCurrentWindowState().home' in f
assert 'if (locked || !enabled || session)' in f
assert 'index>=5' in f
assert 'pager.tracking || pager.dragging || pager.decelerating' in f
assert 'job.observer.cancelsTouchesInView=NO' in f
assert 'self.finished=YES' in f
assert '[self.window removeGestureRecognizer:self.observer]' in f
assert 'snapshotViewAfterScreenUpdates:NO' in f
assert 'self.visited=YES' in f
assert 'setContentOffset:self.original animated:NO' in f
for forbidden in ['NFBUpdateMovieMode(', 'NFBOpenTrollApp(', 'NFBShowDesktopInSplit(', 'kill(']: assert forbidden not in f
m=(r/'Sources/NFBManager.m').read_text()
assert 'NFBObserveHomeWidgetLock(locked, self.enabled)' in m
assert 'NFBObserveMovieLockState' not in m
print('PASS: home-only unlock recovery, six attempts, user touch cancels, teardown restores original page, no movie reopening')
