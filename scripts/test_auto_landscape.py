from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();c=(r/'Sources/NFBSplitCoordinator.m').read_text()
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
assert 'movieDoubleTap' not in m and 'MovieMode' not in m
assert not any(x.get('key')=='MovieMode' for x in p['items'])
assert m.count('movie:YES')==2
assert 'if (self.movieActive && [self.backend desktopActive]) return YES;' in c
assert 'NFBStowMustRestore' not in m
# Only the explicit restore action clears stow; scene changes cannot clear it.
assert m.count('self.railFullyStowed=NO')==1
assert 'CGPointMake(w,MAX(32' in m
assert m.index('[splitCore reconcile]') < m.index('if (self.railFullyStowed && ![self isLocked])')
assert 'stowSwipes' not in m and 'installStowSwipe' not in m
print('PASS: automatic landscape, no independent switch or double tap, stow retained across scenes, half-visible restore handle')
