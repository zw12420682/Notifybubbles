from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
a=m.index('if (keyboardUp != wasUp)');b=m.index('if (!keyboardUp && wasUp)',a)
block=m[a:b]
assert '@[@0.12, @0.32, @0.65]' in block
assert 'manager.movieKeyboardEpoch != epoch' in block
assert '!NFBKeyboardVisible()' in block
assert '!NFBPreference(@"MovieMode", NO)' in block
assert '[manager isLocked]' in block
assert 'NFBRecheckMovieLayout();' in block
assert 'NFBRecheckSplitPlacement' not in block
f=w[w.index('void NFBRecheckMovieLayout(void)'):]
assert 'movieReadAt = 0' in f
assert 'NFBUpdateMovieMode(YES)' in f
print('PASS: 3 bounded movie-only keyboard checks; cancel stale/hidden/disabled mode; bypass throttle')
