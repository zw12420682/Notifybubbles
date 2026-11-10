"""Background swipe must unfold only the collapsed rail, preserving other gestures."""
from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'Sources/NFBManager.m').read_text()
a = s.index('- (void)backgroundUnfoldSwiped:(UISwipeGestureRecognizer *)gesture {')
b = s.index('- (void)desktopActionSwiped:', a)
h = s[a:b]
for token in ['UIGestureRecognizerStateEnded', 'UISwipeGestureRecognizerDirectionLeft', '!self.enabled', '[self isLocked]', 'NFBActionModeCollapsed', 'NFBTrollVisibleApp()', 'NFBActionUnfoldColumn']:
    assert token in h, token
assert '[self.fixedBackgroundHost addGestureRecognizer:self.backgroundUnfoldSwipe]' in s
assert 'self.backgroundUnfoldSwipe.numberOfTouchesRequired = 1' in s
assert 'other == self.fixedBackgroundHost.panGestureRecognizer' in s
assert '[gesture isKindOfClass:UITapGestureRecognizer.class]' in s
assert '[gesture.view isDescendantOfView:self.fixedBackgroundHost]' in s
print('PASS: collapsed-only left swipe, single touch, host-pan coexistence, host tap arbitration')
