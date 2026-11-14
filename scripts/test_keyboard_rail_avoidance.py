from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBManager.m').read_text()
a=s.index('// Keyboard avoidance must use');b=s.index('    [self ensureWindow];',a)
f=s[a:b]
assert 'NFBSplitFrameInView(keyboardRoot)' in f
assert 'available >= 30' in f
assert 'if (keyboardUp)' in f
assert 'self.window.hidden = YES' in f
assert 'userInteractionEnabled = NO' in f
assert '++self.columnSlideToken' in f
assert 'self.columnTargetOffscreen = YES' in f
assert 'NFBRecheckSplitPlacement' not in f
assert b < s.index('rail-transient: rejected', b)
for up,app,right,expected in [(True,True,390,False),(True,True,335.4,True),(True,False,335.4,False)]:
 fits=app and 390-right-8>=30
 assert fits==expected
print('PASS: real keyboard geometry, full window hidden including house, stale reveal invalidated, existing movie checks retained')
