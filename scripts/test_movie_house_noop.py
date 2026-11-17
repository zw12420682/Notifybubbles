from pathlib import Path
r=Path(__file__).resolve().parents[1]
c=(r/'Sources/NFBSplitCoordinator.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
a=c.index('- (BOOL)replaceWindowWithDesktop:');b=c.index('- (void)closeDesktop',a);f=c[a:b]
assert f.index('if (self.movie && [self.backend desktopActive]) return YES;') < f.index('[self beginUserWindowOperation]')
assert '[NFBSplitCoordinator.shared replaceWindowWithDesktop:target]' in m
assert 'self.movieDoubleTap.numberOfTapsRequired = 2' in m
assert '[self.desktopActionTap requireGestureRecognizerToFail:self.movieDoubleTap]' in m
print('PASS: movie desktop house single tap no-op before side effects; mode double-tap arbitration retained')
