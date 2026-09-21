"""Dependency-free repository validation; does not substitute for iOS compilation."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
required = [
    'Makefile', 'control', 'Sources/NFBAppExit.h', 'Sources/NFBAppExit.m',
    # Retired app-side back helper: kept on disk so it can be restored, but the
    # Makefile must not build it (see the assertions below).
    'NotifyBubblesBack.plist', 'Sources/NFBAppBack.m',
    'Sources/NFBBackRequest.m', 'Sources/NFBBackRequest.h', 'Sources/NFBBackProtocol.h',
    'Sources/NFBNotificationPolicy.m', 'Sources/NFBNotificationPolicy.h', 'NotifyBubbles.plist', 'Sources/Tweak.m',
    'Sources/NFBTrollOpen.h', 'Sources/NFBTrollOpen.m', 'Tests/TrollOpenTests.m',
    'Sources/NFBGeometry.h', 'Sources/NFBSwitcher.h', 'Sources/NFBSwitcher.m',
    'Sources/NFBDebugLog.h', 'Sources/NFBKeyboard.h', 'Sources/NFBKeyboard.m',
    'Sources/NFBManager.m', 'Sources/NFBStore.m', 'Preferences/Makefile',
    'Preferences/NFBPreferences.m', 'Preferences/Resources/Root.plist',
    'Preferences/Resources/Info.plist', '.github/workflows/build.yml',
    'layout/Library/PreferenceLoader/Preferences/NotifyBubbles.plist',
]
for name in required:
    assert (root / name).is_file(), f'Missing {name}; upload the project CONTENTS to repository root.'
for path in root.rglob('*.plist'):
    if any(part.startswith('.theos') for part in path.parts):
        continue
    with path.open('rb') as stream:
        plistlib.load(stream)
control_bytes = (root / 'control').read_bytes()
assert b'\r' not in control_bytes, 'control must use Unix LF line endings; upload the corrected control file.'
assert control_bytes.endswith(b'\n'), 'control must end with a newline.'
assert not control_bytes.startswith(b'\xef\xbb\xbf'), 'control must be UTF-8 without BOM.'
control = dict(line.split(': ', 1) for line in control_bytes.decode('utf-8').splitlines() if ': ' in line)
assert control['Architecture'] == 'iphoneos-arm64e'
assert 'THEOS_PACKAGE_SCHEME = roothide' in (root / 'Makefile').read_text()
assert 'Sources/NFBSwitcher.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for 0.35.0.'
assert 'Sources/NFBKeyboard.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for the keyboard watcher.'
assert 'Sources/NFBTrollOpen.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for TrollOpen integration.'
assert 'Sources/NFBAppExit.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for the exit helper.'
# The app-side back helper is retired: it filtered on com.apple.UIKit, so it was
# loaded into every app, and no gesture drives it any more.
assert 'NotifyBubblesBack_FILES' not in (root / 'Makefile').read_text(), \
    'NotifyBubblesBack is retired; do not build it into every app again.'
assert 'TWEAK_NAME = NotifyBubbles\n' in (root / 'Makefile').read_text(), \
    'TWEAK_NAME must only build NotifyBubbles (the app-side back helper is retired).'
prefs = plistlib.loads((root / 'Preferences/Resources/Root.plist').read_bytes())
assert {x['key'] for x in prefs['items'] if 'key' in x} == {'Enabled','ShowOnLock','ShowOnHome','ShowInApps','IconSize','IconOpacity','VerticalPosition'}
filter_ = plistlib.loads((root / 'NotifyBubbles.plist').read_bytes())
assert filter_['Filter']['Bundles'] == ['com.apple.springboard']
print('PASS: required files, property lists, RootHide configuration, preference keys and injection filter')
