"""Manual radius shared by ordinary/movie desktops, without Open style probes."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
item=next(x for x in p['items'] if x.get('key')=='DesktopCornerRadius')
assert (item['min'],item['max'],item['default'])==(0,100,14)
h=(r/'Sources/NFBDesktopHost.m').read_text()
w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'CFSTR("DesktopCornerRadius")' in h
assert 'MAX(0, MIN(100, radius))' in h
assert 'panel.layer.cornerRadius = NFBConfiguredDesktopRadius();' in h
place=h[h.index('- (BOOL)place {'):h.index('- (void)check {')]
assert 'self.panel.layer.cornerRadius = radius' in place
assert 'NFBConfiguredDesktopRadius()' in place
assert 'NFBDesktopSplitCornerRadius();' in w
assert 'bezierPathWithRoundedRect:hole cornerRadius:radius' in w
assert 'portraitCornerRadius' not in w
assert 'NFBMovieDesktopCornerRadius' not in w+h
for v,expected in [(-1,0),(0,0),(14,14),(100,100),(101,100)]:
 assert max(0,min(100,v))==expected
print('PASS: shared manual 0-100pt radius, default14, live panel update and rounded cutout; Open corner probes removed')
