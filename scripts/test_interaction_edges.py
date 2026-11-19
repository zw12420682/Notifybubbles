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
x=method('- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {','- (NFBActionMode)desktopActionMode')
assert '[self.store clear]' not in x
assert x.index('showOpenNotice:') < x.index('return;\n    }') < x.index('closeDesktop') < x.index('closeCurrentWindow')
print('PASS: upward swipe intent, hidden visual reminders, and no notification clearing from split X')
