from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text()
w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'self.movieDoubleTap.numberOfTapsRequired = 2' in m
assert '[self.desktopActionTap requireGestureRecognizerToFail:self.movieDoubleTap]' in m
assert 'CFPreferencesSetAppValue(CFSTR("MovieMode")' in m
assert 'UIColor.systemRedColor : UIColor.systemGreenColor' in m
assert 'movieFit' not in m
assert 'plan.favoritesVisible =' not in m
assert 'movieSquare' not in w
movie=w[w.index('// Movie layout is opt-in'):]
assert 'cornerRadius =' not in movie
assert 'basis.a /= sx' in movie and 'basis.c /= sy' in movie
assert 'area.size.width * 0.86, area.size.height * 0.86' in movie
assert 'portraitRailReference toView:parent' in movie
assert 'width = height *' not in movie
print('PASS: double tap excludes single tap, persisted mode color, two rails, no corner mutation, absolute scale and desktop aspect')
