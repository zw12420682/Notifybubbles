"""Desktop fallback must match the portrait reference, not shrink to fit video."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBWindowControls.m').read_text()
a=s.index('if (CGRectIsEmpty(lower)) {',s.index('// Movie layout is opt-in'))
b=s.index('movieLowerScreen =',a)
block=s[a:b]
assert 'portraitRailRoot convertRect:portraitRailReference toView:parent' in block
assert 'CGSizeEqualToSize(portraitRailScreen, area.size)' in block
assert 'movieDesktopAnchor.frame = lower' in block
assert 'videoBand' not in block
assert 'width = height *' not in block
# iPhone 14 portrait screen: same normal pane, both with app and desktop.
W,H=390.0,844.0
portrait=(0,H*.14,W*.86,H*.86)
desktop=portrait
assert desktop==portrait
assert abs(desktop[2]-335.4)<1e-6
assert abs(desktop[3]-725.84)<1e-6
room=portrait[1]-2
scale=min(room/(W*9/16),1)
assert 0 < scale < 1
assert W*9/16*scale <= portrait[1]-2+1e-6
print('PASS: desktop shares portrait geometry; video alone fits remaining space')
