from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBWindowControls.m').read_text()
a=s.index('CGRect lower=NFBMovieStandardPane(area);');b=s.index('// Keep the desktop anchor stable.',a)
assert 'movieDesktopAnchor.frame = lower' in s[a:b]
assert 'portraitRailReference' not in s[a:b] and 'moviePortrait' not in s[a:b]
assert 'NFBReplaceMoviePaneWithAnchor(window, retained, anchor)' in s
print('PASS: stable movie pane used independently of transient portrait, including house action')

keyboard=s[b:s.index('movieLowerScreen =',b)]
assert 'NFBKeyboardVisible() && moviePortrait.window' in keyboard
assert 'convertRect:moviePortrait.bounds toView:parent' in keyboard
assert 'if (NFBMovieValidLower(keyboardLower,area)) lower=keyboardLower;' in keyboard
assert 'movieDesktopAnchor.frame' not in keyboard
