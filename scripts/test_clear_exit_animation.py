"""The visible exit stays independent of live rows and fades only in its latter half."""
from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'Sources/NFBManager.m').read_text()
a = s.index('- (void)sweepAwayBubbles:', s.index('// The single teardown'))
b = s.index('// "一键清理后台"', a)
s = s[a:b]
assert 'snapshotViewAfterScreenUpdates:NO' in s
assert 'exitOverlay.userInteractionEnabled = NO' in s
assert 'animateKeyframesWithDuration:0.35' in s
assert 'CGAffineTransformMakeScale(0.30, 0.30)' in s
assert 'addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5' in s
completion = s[s.index('completion:^'):]
assert '[exitOverlay removeFromSuperview]' in completion
assert 'self.store' not in completion
print('PASS: 350ms independent exit, shrink to 30%, fade in latter half, completion only removes overlay')
