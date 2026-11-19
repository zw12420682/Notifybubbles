from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text()
a=m.index('- (BOOL)railStowEligible {');b=m.index('- (void)clearAllTapped:',a);f=m[a:b]
assert 'NFBStowCanBegin' in f and 'NFBStowMustRestore' in m
assert 'self.railWasExpandedBeforeStow=self.edgeExpanded' in f
assert 'self.railFullyStowed=YES' in f and 'self.railFullyStowed=NO' in f
assert 'self.edgeExpanded=self.railWasExpandedBeforeStow' in f
assert 'chevron.left' in m and 'CGPointMake(w-24,MAX(32' in m
for view in ['self.rail','self.fixedBackgroundHost','self.favoritesRail','button']:
    assert '[self installStowSwipeOnView:'+view+']' in m
assert 'installStowSwipeOnView:self.window' not in m
assert 'installStowSwipeOnView:self.window.rootViewController.view' not in m
assert 'stowRoot.hidden=YES' in m and 'self.desktopActionButton.hidden=YES' in m
assert 'NFBSetCaptureHidden(self.railStowHandle,self.hideInScreenshots)' in m
w0=m[m.index('@implementation NFBWindow'):m.index('@end',m.index('@implementation NFBWindow'))]
assert 'if (hit == self || hit == self.rootViewController.view) return nil;' in w0
print('PASS: main-rail-only home stow, mode guards, restore state, and window passthrough')
