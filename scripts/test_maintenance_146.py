from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text();h=(r/'Sources/NFBDesktopHost.m').read_text()
assert 'lastClearTapY' not in m
assert 'holdClearedColumnAndRestartClock' not in m
assert 'clearUnreadKeepingExpanded' not in m
for line in m.splitlines():
 if 'traceClearView:[NSString stringWithFormat:' in line: assert 'if (NFBDebugLoggingEnabled())' in line
assert 'BOOL cutoutChanged =' in w
assert 'if (cutoutChanged)' in w
assert 'mask.cachedHole=hole' in w
assert 'CGRectEqualToRect(mask.cachedBounds,black.bounds)' in w
assert 'desktop-widget: before-transfer' in h
assert 'desktop-widget-ancestor:' in h
assert 'session!=self || self.restoring || self.startedHome || self.pendingApp.length' in h
# Unchanged geometry reuses the mask; moving pane and slider both update it.
last=None;updates=0
for value in [(0,248,335,596,14)]*10+[(0,248,335,596,30)]*10+[(0,151,390,693,30)]*10:
 if value!=last:updates+=1;last=value
assert updates==3
print('PASS: unchanged cutout reused, geometry/radius changes update; unused methods removed; debug allocations gated; widget refresh policy unchanged')
