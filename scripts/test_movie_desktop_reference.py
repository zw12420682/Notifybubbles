from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBWindowControls.m').read_text()
a=s.index('CGRect lower=NFBMovieStandardPane(area);');b=s.index('movieLowerScreen =',a)
assert 'movieDesktopAnchor.frame = lower' in s[a:b]
assert 'portraitRailReference' not in s[a:b] and 'moviePortrait' not in s[a:b]
assert 'NFBReplaceMoviePaneWithAnchor(window, retained, anchor)' in s
print('PASS: stable movie pane used independently of transient portrait, including house action')
