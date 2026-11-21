from pathlib import Path
r=Path(__file__).resolve().parents[1]
w=(r/'Sources/NFBWindowControls.m').read_text();d=(r/'Sources/NFBDesktopHost.m').read_text()
b=w.split('moviePortrait=observation.portrait;',1)[1].split('if (!movieIsActive)',1)[0]
assert 'NFBSetMovieDesktopParked(movieDesktopSession, moviePortrait != nil)' in b
assert 'NFBCloseDesktopSplit' not in b and 'removeFromSuperview' not in b
p=d.split('void NFBSetMovieDesktopParked(',1)[1].split('static UIScrollView *NFBDesktopPager',1)[0]
for forbidden in ('NFBShowDesktopInSplit','addSubview','refreshWidgetPage','activateDesktop','animateWithDuration'):
 assert forbidden not in p,forbidden
assert 'session.identifier!=identifier' in p
assert 'active.panel.hidden=YES' in p and 'active.panel.hidden=NO' in p
assert 'active.widgetRefreshCancelled=YES' in p
assert 'active.pendingApp=nil' in p
assert 'if (self.restoring || self.movieParked) return;' in d
assert 'if (active.movieParked)' in d
assert 'if (self.moviePersistent)' in d
assert '!NFBMovieDesktopParked()' in w
s=(r/'Sources/NFBHomeSwipeClose.m').read_text()
assert '.generation' not in s and '.operationEpoch' in s
print('PASS: movie-owned same-session desktop parking; no re-transplant, refresh or opening animation; safe focus/touch gates')
