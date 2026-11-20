from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();p=(r/'Preferences/Resources/Root.plist').read_text();v=(r/'Preferences/NFBPreferences.m').read_text()
assert 'ShowOnLock' not in m+p+v
assert 'showLock' not in m
s=m[m.index('- (BOOL)shouldShow {'):m.index('- (void)ensureWindow {')]
assert 'if (NFBCheckedBool(lock, @"isUILocked", YES)) return NO;' in s
assert 'self.showLock' not in s
assert 'NFBCheckedBool(lock, @"isUILocked", YES)' in m
print('PASS: lock-screen display option removed; locked overlay always hides; safety checks remain')
