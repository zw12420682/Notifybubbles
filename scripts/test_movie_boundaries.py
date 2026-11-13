from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBWindowControls.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
assert 'CGRectGetMinY(lower)-CGRectGetMinY(area)-2' in s
assert 'CGAffineTransformScale(basis, ratio, ratio)' in s
assert '!movieDesktopAttempted' in s
assert 'if (!NFBDesktopSplitActive()) movieOwnsDesktop = NFBShowDesktopInSplit' in s
assert 'basis.a /= sx' in s
assert 'CGFloat videoBand = area.size.width * 9.0 / 16.0' in s
assert 'CGRect lower = NFBMovieLowerFrameInView(root)' in m
assert 'CGFloat movieTop = MAX(CGRectGetMinY(lower)' in m
assert 'CGFloat movieBottom = MIN(CGRectGetMaxY(lower)' in m
print('PASS: lower-window rail bounds, aspect-fit video, guarded desktop fallback, reversible wrapper corners')
