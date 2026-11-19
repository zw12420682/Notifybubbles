from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text()
a=m.index('- (BOOL)railStowEligible {');b=m.index('- (void)clearAllTapped:',a);f=m[a:b]
assert 'NFBStowCanBegin' in f and 'NFBStowMustRestore' not in m
assert 'self.railWasExpandedBeforeStow=self.edgeExpanded' in f
assert 'self.railFullyStowed=YES' in f and 'self.railFullyStowed=NO' in f
assert 'self.edgeExpanded=self.railWasExpandedBeforeStow' in f
assert 'chevron.left' in m and 'CGPointMake(w,MAX(32' in m
assert 'installStowSwipeOnView' not in m and 'stowSwipes' not in m
assert 'railStowSwipeRecognized' not in m
h=m[m.index('- (void)desktopActionHeld:(UILongPressGestureRecognizer *)gesture {'):m.index('- (void)backgroundUnfoldSwiped:(UISwipeGestureRecognizer *)gesture {')]
assert 'enterRailStow' not in h and 'NFBActionHold' in h
assert 'UIGestureRecognizerStateBegan' in h
up=m[m.index('- (void)desktopActionUpSwiped:(UISwipeGestureRecognizer *)gesture {'):m.index('- (void)desktopActionSwiped:(UISwipeGestureRecognizer *)gesture {')]
assert 'if (self.desktopActionToggle)' in up and '[self enterRailStow]' in up
assert up.index('[self enterRailStow]') < up.index('rotateWindow:target')
assert 'UISwipeGestureRecognizerDirectionUp' in up
assert 'stowRoot.hidden=YES' in m and 'self.desktopActionButton.hidden=YES' in m
assert 'NFBSetCaptureHidden(self.railStowHandle,self.hideInScreenshots)' in m
w0=m[m.index('@implementation NFBWindow'):m.index('@end',m.index('@implementation NFBWindow'))]
assert 'if (hit == self || hit == self.rootViewController.view) return nil;' in w0
print('PASS: main-rail-only home stow, mode guards, restore state, and window passthrough')
