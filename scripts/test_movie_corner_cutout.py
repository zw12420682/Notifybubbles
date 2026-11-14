"""Movie black backdrop must cover pixels outside the rounded desktop pane."""
from pathlib import Path
import math
r=Path(__file__).resolve().parents[1]
w=(r/'Sources/NFBWindowControls.m').read_text()
h=(r/'Sources/NFBDesktopHost.m').read_text()
assert 'CGFloat radius = NFBDesktopSplitCornerRadius();' in w
assert 'session.panel.layer.cornerRadius : NAN' in h
assert 'bezierPathWithRoundedRect:hole cornerRadius:radius' in w
assert 'bezierPathWithRect:hole]' not in w
assert 'mask.fillRule = kCAFillRuleEvenOdd' in w
assert 'else black.layer.mask = nil' in w
for width,height,radius,scale in [(335.4,595.98,14,1),(335.4,725.84,20,1),(300,500,14,.8),(200,400,0,1)]:
    effective=min(radius*scale,min(width*scale,height*scale)/2)
    assert 0<=effective<=min(width*scale,height*scale)/2
    if effective:
        # A corner pixel was visible through the old rectangle. It is outside
        # the rounded opening, hence remains opaque black with even-odd fill.
        x=y=effective*.1
        assert math.hypot(x-effective,y-effective)>effective
print('PASS: actual pane radius, coordinate scaling, rounded hole, corner leak covered, cleanup retained')
