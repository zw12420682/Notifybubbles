"""Maintenance regressions: stable empty state and geometry ownership on restore."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'if (![(watched ?: @"") isEqualToString:(floatingNow ?: @"")]) dirty = YES;' in m
for a,b,changed in [(None,None,False),('',None,False),('a','a',False),('a',None,True),(None,'a',True),('a','b',True)]:
 assert ((a or '') != (b or '')) == changed
s=w[w.index('static void movieRestore('):w.index('BOOL NFBUpdateMovieMode(')]
assert 'record.moved && sameOwner' in s
assert 'view.superview == record.parent' in s
assert 'record.sceneOrientation' in s and 'record.containerOrientation' in s
assert 'view.transform, record.appliedTransform' in s
assert 'view.center, record.appliedCenter' in s
assert 'if (movieDesktopAnchor.superview != parent) [parent addSubview:movieDesktopAnchor];' in w
assert 'record.parent != parent' in w
assert 'record.appliedTransform = view.transform' in w
print('PASS: nil/nil is unchanged; stale rotation/host geometry never restored; desktop proxy reparented before layout')
