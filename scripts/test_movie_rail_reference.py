from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBWindowControls.m').read_text()
a=s.index('CGRect NFBSplitFrameInView(');b=s.index('BOOL NFBSplitFrameClassUnavailable',a)
f=s[a:b]
assert 'view = movieDesktopAnchor' not in f
assert 'portraitRailReference = frame' in f
assert 'CGSizeEqualToSize(portraitRailScreen, root.bounds.size)' in f
assert 'return portraitRailReference' in f
assert 'size.width * 0.86, size.height * 0.86' in f
# Same real portrait -> same input even when the desktop proxy is narrower.
portrait=(0,248.02,335.4,595.98)
proxy=(0,220.0,288.0,624.0)
rail_reference=portrait
assert rail_reference==portrait and rail_reference!=proxy
m=(r/'Sources/NFBManager.m').read_text()
assert 'movieFit' not in m
assert 'CGFloat movieSide' not in m
print('PASS: movie desktop cannot supply rail geometry; real portrait reference retained; orientation changes reject stale reference')
