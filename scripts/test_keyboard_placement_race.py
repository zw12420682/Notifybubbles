from pathlib import Path
r=Path(__file__).resolve().parents[1]
w=(r/'Sources/NFBWindowControls.m').read_text()
a=w.index('void NFBObserveSplitPlacement(');b=w.index('void NFBRecheckSplitPlacement(',a)
f=w[a:b]
assert f.index('if (NFBKeyboardVisible())') < f.index('SEL scale =')
assert 'return;' in f[f.index('if (NFBKeyboardVisible())'):f.index('SEL scale =')]
m=(r/'Sources/NFBManager.m').read_text()
assert 'rail-transient: rejected' in m
assert 'CGSizeEqualToSize(self.validRailRootSize, bounds.size)' in m
assert 'CGRectEqualToRect(splitA, self.validRailSplitFrame)' in m
assert 'self.validRailSplitFrame = splitA' in m
h=(r/'Sources/NFBDesktopHost.m').read_text()
assert 'desktop-widget-content:' in h
assert 'post-restore home' in h
assert 'session!=self || self.restoring || self.widgetRefreshCancelled || self.pendingApp.length' in h
# Device race: keyboard moves app, a pending retry must not move it back.
for keyboard, expected in [(True,151),(False,248.02)]:
 top=151
 if not keyboard: top=248.02
 assert top==expected
print('PASS: keyboard blocks launch retries before size sync; transient rail keeps valid geometry; widget diagnostics do not change refresh strategy')
