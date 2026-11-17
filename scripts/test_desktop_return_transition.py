from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'Sources/NFBDesktopHost.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
a=h.index('void NFBCloseMovieDesktopWithTransition(');b=h.index('BOOL NFBDesktopSplitActive(',a);f=h[a:b]
assert 'session.identifier!=identifier' in f
assert 'NFBCurrentWindowState().home' in f
assert 'NFBDesktopAnimationsEnabled()' in f
assert f.index('NFBCloseDesktopSplit();')<f.index('animateWithDuration:0.28')
assert 'cover.userInteractionEnabled=NO' in f
completion=f[f.index('completion:^'):]
for forbidden in ('restore]', 'makeKey', 'windowLevel =', 'NFBCloseDesktopSplit()', 'session ='):
 assert forbidden not in completion,forbidden
assert 'desktopReturnToken==token' in completion
assert 'enabled && explicitlyClosed' in w
assert 'NFBUpdateDesktopReturnTransition(NO)' in h
assert 'NFBUpdateDesktopReturnTransition(self.enabled' in m
print('PASS: auto movie exit only, synchronous real restore, disposable noninteractive 280ms cover, cancellation and token cleanup')
