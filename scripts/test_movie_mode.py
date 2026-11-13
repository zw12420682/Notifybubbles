"""Movie mode is opt-in, layout-only, and cannot overwrite ordinary rail metrics."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBWindowControls.m').read_text()
m=(r/'Sources/NFBManager.m').read_text()
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
option=next(x for x in p['items'] if x.get('key')=='MovieMode')
assert option['default'] is False
movie=s[s.index('// Movie layout is opt-in'):]
for token in ('movieRestore(view)', 'view.layer.cornerRadius = record.radius',
              'view.center = record.center', 'black.userInteractionEnabled = NO',
              'UIColor.blackColor', 'sceneOrientation', 'containerOrientation',
              'miniWindowModeEnabled', 'isClosingWithKeepAliveAnimation'):
    assert token in movie, token
for token in ('terminateApplication:', 'setSceneOrientation:', 'makeKeyAndVisible', 'setVisualScale:'):
    assert token not in movie, token
assert 'BOOL validRailMeasurement = !movieActive &&' in m
assert 'if (movieActive && splitNow)' in m
assert 'movieBottom - movieSide - movieGap - plan.rowsTop' in m
print('PASS: movie option defaults off; reversible layout; no lifecycle/rotation calls; ordinary rail cache isolated')
