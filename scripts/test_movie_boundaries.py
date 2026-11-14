from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBWindowControls.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
assert 'const CGFloat movieGap = 4.0;' in s
assert 'CGRectGetMinY(lower)-CGRectGetMinY(area)-movieGap' in s
assert 'CGRectGetMinY(lower) - movieGap - h*ratio/2' in s
assert 'CGAffineTransformScale(basis, ratio, ratio)' in s
assert '!movieDesktopAttempted' in s
assert 'if (!NFBDesktopSplitActive()) movieOwnsDesktop = NFBShowDesktopInSplit' in s
assert 'basis.a /= sx' in s
assert 'CGFloat videoBand =' not in s
assert '[portraitRailRoot convertRect:portraitRailReference toView:parent]' in s
assert 'NFBMovieLowerFrameInView(root)' not in m
assert 'BOOL hideForPosition = floatingApp.length && !atBottomLeft;' in m
print('PASS: video aspect-fit above unchanged portrait; desktop fallback; original rail position gate')
