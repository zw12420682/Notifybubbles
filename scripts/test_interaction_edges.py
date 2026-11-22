from pathlib import Path
m=(Path(__file__).resolve().parents[1]/'Sources/NFBManager.m').read_text()
def method(a,b):
 i=m.index(a);return m[i:m.index(b,i)]
up=method('- (void)desktopActionUpSwiped:(UISwipeGestureRecognizer *)gesture {','- (void)desktopActionSwiped:')
assert up.index('self.desktopActionToggle!=startedOnArrow') < up.index('[self enterRailStow]') < up.index('rotateWindow:target')
assert 'target!=NFBDesktopActionWindow()' in up
assert 'self.nfbUpSwipeStartedOnStowArrow=[self railStowEligible] &&' in m
assert 'if (self.desktopActionToggle!=toggleMode)' in m
assert 'if (!self.railFullyStowed) [self.pendingBurstApps addObject:appID];' in m
assert 'self.railFullyStowed=YES;\n    [self.pendingBurstApps removeAllObjects];' in m
assert 'clearAllTapped:' not in m and 'NFBClearAllID' not in m
assert '[self clearBackground];' in m
print('PASS: upward swipe intent, hidden reminders, no split X, existing background cleanup retained')
