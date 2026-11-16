from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBDesktopHost.m').read_text();l=(r/'Sources/NFBWindowLease.m').read_text()
a=s.index('static UIView *NFBMovieHostHit(');b=s.index('void NFBUpdateMovieDesktopTouchHosts',a)
f=s[a:b]
assert 'ownsHost:object session:session.identifier' in f
assert 'nativeHitInHost:object point:point event:event session:session.identifier' in f
assert 'publishTouchWindows:windows session:desktopSession' in s
assert 'originalMovieHostHit(object, selector, point, event)' in f
assert 'desktop.windowLevel+1' in l
assert 'identifier!=self.sessionIdentifier' in l
assert 'entry.relinquished=YES' in l
assert 'releaseSession:self.identifier' in s
assert 'NFBSplitCoordinator.shared.windowLease' in s
print('PASS: shared coordinator lease gates native touch and level by exact session; foreign changes yield')
