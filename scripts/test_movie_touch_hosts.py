from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBDesktopHost.m').read_text()
w=(r/'Sources/NFBWindowControls.m').read_text()
a=s.index('static UIView *NFBMovieHostHit(');b=s.index('static void NFBRestoreMovieHosts',a)
f=s[a:b]
assert 'session && !session.restoring && [movieHostLevels objectForKey:object]' in f
assert 'NFBDesktopFloatingHit(object, nil, cls, object, point, event)' in f
assert 'originalMovieHostHit(object, selector, point, event)' in f
assert 'session.window.windowLevel + 1' in s
assert 'host == session.window' in s
assert 'fabs(host.windowLevel - applied) < 0.01' in s
assert '- (void)restore {\n    NFBRestoreMovieHosts();' in s
assert 'movieIsActive && movieOwnsDesktop && NFBDesktopSplitActive()' in w
assert 'NFBUpdateMovieDesktopTouchHosts(touchHosts)' in w
print('PASS: auto-movie session only; native same-window floating hits; level ownership restoration; no event forwarding')
