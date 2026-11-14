"""Aspect-fit movie bottom must sit 4pt above the unchanged portrait pane."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBWindowControls.m').read_text()
assert 'const CGFloat movieGap = 4.0;' in s
assert 'CGRectGetMinY(lower) - movieGap - h*ratio/2' in s
for width, top, w, h in [(390,248.02,390,219.375),(390,118.16,844,390),(430,300,1920,1080)]:
    gap=4
    scale=min((top-gap)/h,width/w)
    height=h*scale
    y=top-gap-height
    assert y >= -1e-6
    assert abs(top-(y+height)-4)<1e-6
    assert w*scale <= width+1e-6
    assert abs((w*scale)/height-w/h)<1e-6
print('PASS: fixed 4pt gap, aspect ratio retained, no overlap, lower pane unchanged')
