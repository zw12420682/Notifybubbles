"""Dependency-free repository validation; does not substitute for iOS compilation."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parents[1]
required = [
    "Sources/NFBTopAction.h",
    "Sources/NFBRightEdgeAction.h",
    "layout/DEBIAN/postinst",
    'Sources/NFBSplitClosePolicy.h', 'Sources/NFBWindowControls.h', 'Sources/NFBWindowControls.m', 'Sources/NFBStorageLayout.h', 'Sources/NFBEdgeInspection.h', 'Makefile', 'control', 'Sources/NFBAppExit.h', 'Sources/NFBAppExit.m',
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
assert 'Sources/NFBSwitcher.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for 0.40.0.'
assert 'Sources/NFBKeyboard.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for the keyboard watcher.'
assert 'Sources/NFBTrollOpen.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for TrollOpen integration.'
assert 'Sources/NFBAppExit.m' in (root / 'Makefile').read_text(), 'Update the root Makefile for the exit helper.'
assert 'NotifyBubblesBack_FILES' not in (root / 'Makefile').read_text()
assert 'Sources/NFBBackRequest.m' not in (root / 'Makefile').read_text()
prefs = plistlib.loads((root / 'Preferences/Resources/Root.plist').read_bytes())
assert {x['key'] for x in prefs['items'] if 'key' in x} == {'Enabled','ShowOnLock','ShowOnHome','ShowInApps','IconSize','IconOpacity','ClosePreviousSplit','FreezeDesktop','HideInScreenshots','DesktopBlurTransparency','DebugLogging'}
filter_ = plistlib.loads((root / 'NotifyBubbles.plist').read_bytes())
assert filter_['Filter']['Bundles'] == ['com.apple.springboard']
print('PASS: required files, property lists, RootHide configuration, preference keys and injection filter')

assert 'NotifyBubblesKeyboard_FILES' not in (root / 'Makefile').read_text()

assert (root / "Sources/NFBPrivacy.m").is_file()
assert "Sources/NFBPrivacy.m" in (root / "Makefile").read_text()

for relative in ['Sources/NFBOpenEdge.m', 'Sources/NFBWindowControls.m', 'Sources/NFBEdgeInspection.h', 'Sources/NFBRightEdgeAction.h', 'Sources/NFBTopAction.h']:
    source = (root / relative).read_text(encoding='utf-8')
    for forbidden in ['class_getInstanceVariable', 'object_getIvar', 'ivar_getOffset', 'valueForKey:@"_targets"', 'NSStringFromSelector']:
        assert forbidden not in source, f'Unsafe gesture action inspection reintroduced: {relative}: {forbidden}'
print('PASS: close adapter and edge diagnostics do not read private gesture action pointers')

assert control["Version"] == "0.48.33"
assert plistlib.loads((root/"Preferences/Resources/Info.plist").read_bytes())["CFBundleVersion"] == control["Version"]
for name in ["NFBDebugLog.m", "NFBWindowState.m"]:
    assert "Sources/" + name in (root/"Makefile").read_text()
print("PASS: current version and new runtime sources")

adapter = (root / "Sources/NFBTrollOpen.m").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/build.yml").read_text(encoding="utf-8")
assert "TARGET_OS_OSX && !defined(NFB_PORTABLE_ADAPTER_TEST)" in adapter
assert "#define NFBDebugLog NFBAdapterDebugLog" in adapter
assert "#define NFBErrorLog NFBAdapterErrorLog" in adapter
assert "Sources/NFBTrollOpen.m" in workflow and "Tests/TrollOpenTests.m" in workflow
print("PASS: automatic macOS adapter isolation; both old and current test commands supported")
