from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
s = (r/'Sources/NFBArcDiagnostics.h').read_text()
assert 'sample < 5' in s and 'sample * 6 * NSEC_PER_SEC' in s
assert 'epoch != nfbArcEpoch || !NFBDebugLoggingEnabled()' in s
assert 'NFBCheckedBool(lock, @"isUILocked", YES)' in s
assert '*visited >= 1800' in s and '*emitted >= 120' in s and 'depth > 28' in s
assert 'count++ >= 48' in s
for forbidden in ['setWindowLevel:', 'setHidden:', 'setAlpha:', 'setUserInteractionEnabled:',
                  'hitTest:', 'sendAction:', 'addGestureRecognizer:', 'MSHookMessageEx',
                  'accessibilityLabel', '.text', 'recursiveDescription']:
    assert forbidden not in s, forbidden
for required in ['window.windowLevel', 'view.layer.zPosition', 'indexOfObjectIdenticalTo:',
                 'NFBArcImage(view.class)', 'view.gestureRecognizers', 'scope=SpringBoard-only']:
    assert required in s, required
p = plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
assert sum(x.get('action') == 'captureArcHierarchy' for x in p['items']) == 1
assert 'CFSTR("local.notifybubbles/arc-diagnostics")' in (r/'Sources/Tweak.m').read_text()
assert 'CFSTR("local.notifybubbles/arc-diagnostics")' in (r/'Preferences/NFBPreferences.m').read_text()
print('PASS: ARC diagnostics explicitly armed, read-only, debug/lock guarded, bounded, private text excluded')
