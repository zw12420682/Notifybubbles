from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text()
w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'movieDoubleTap' not in m
assert 'movieDoubleTapped:' not in m
assert 'movie:YES' in m and 'CFSTR("MovieMode")' not in m
assert 'UIColor.systemRedColor : UIColor.systemGreenColor' in m
assert 'movieFit' not in m
assert 'plan.favoritesVisible =' not in m
assert 'movieSquare' not in w
movie=w[w.index('// Movie layout is opt-in'):]
assert 'cornerRadius =' not in movie
assert 'basis.a /= sx' in movie and 'basis.c /= sy' in movie
assert 'CGRect lower=NFBMovieStandardPane(area);' in movie
assert 'portraitRailReference toView:parent' not in movie
assert 'width = height *' not in movie
print('PASS: double tap excludes single tap, persisted mode color, two rails, no corner mutation, absolute scale and desktop aspect')
