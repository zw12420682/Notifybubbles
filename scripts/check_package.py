"""Runs on the macOS builder after packaging. Fail rather than upload an empty DEB.

Usage:
    python3 scripts/check_package.py [--scheme rootless|roothide] [--arch iphoneos-arm64[e]] DEB...

--scheme / --arch pin the expected control Architecture. Without them both
supported values are accepted, so the same script validates rootless
(iphoneos-arm64, /var/jb) and roothide (iphoneos-arm64e, RootHide) builds.
When --scheme is given the payload prefix must match the scheme too
(/var/jb/... for rootless, plain /... for roothide).
"""
import argparse
import subprocess
import sys
from pathlib import Path
import io, tarfile, plistlib
from macho import architectures, ARM64

SCHEMES = {'rootless': 'iphoneos-arm64', 'roothide': 'iphoneos-arm64e'}
ARCHITECTURES = tuple(SCHEMES.values())

parser = argparse.ArgumentParser(description='Verify a packaged NotifyBubbles DEB.')
parser.add_argument('--scheme', choices=sorted(SCHEMES), default=None,
                    help='Expected packaging scheme (implies --arch).')
parser.add_argument('--arch', choices=list(ARCHITECTURES), default=None,
                    help='Expected control Architecture (default: accept both).')
parser.add_argument('debs', nargs='+')
arguments = parser.parse_args()
if arguments.scheme and arguments.arch and SCHEMES[arguments.scheme] != arguments.arch:
    parser.error('--scheme %s conflicts with --arch %s' % (arguments.scheme, arguments.arch))
expected_architecture = arguments.arch or (SCHEMES[arguments.scheme] if arguments.scheme else None)
accepted = (expected_architecture,) if expected_architecture else ARCHITECTURES

assert arguments.debs, 'No DEB supplied'
for argument in arguments.debs:
    path = Path(argument)
    assert path.is_file(), f'Missing package: {path}'
    expected = dict(line.split(': ',1) for line in (Path(__file__).resolve().parents[1]/'control').read_text().splitlines() if ': ' in line)['Version']
    version = subprocess.check_output(['dpkg-deb','-f',str(path),'Version'],text=True).strip()
    assert version == expected, f'Incorrect package version: {version}'
    architecture = subprocess.check_output(['dpkg-deb', '-f', str(path), 'Architecture'], text=True).strip()
    assert architecture in accepted, f'Incorrect architecture: {architecture} (expected {" or ".join(accepted)})'
    scheme = next((name for name, value in SCHEMES.items() if value == architecture), None)
    payload = subprocess.check_output(['dpkg-deb', '-c', str(path)], text=True)
    assert 'NotifyBubblesBack.dylib' not in payload, 'Retired return helper still packaged.'
    assert 'NotifyBubblesBack.plist' not in payload, 'Retired return filter still packaged.'
    assert 'NotifyBubblesKeyboard.dylib' not in payload, 'Retired keyboard theme is still in the DEB.'
    assert 'NFBKeyboardDock.dylib' not in payload and 'NFBKeyboardDock.plist' not in payload, 'Stopped keyboard module must not ship.'
    if scheme:
        # rootless installs under /var/jb, roothide uses the bootstrap root.
        expected_root = 'var/jb/' if scheme == 'rootless' else None
        if expected_root:
            assert expected_root in payload, f'rootless payload must live under /var/jb: {path.name}'
        else:
            assert 'var/jb/Library/MobileSubstrate/DynamicLibraries/NotifyBubbles.dylib' not in payload, \
                'roothide payload must not use the /var/jb prefix'
    for suffix in ['NotifyBubbles.dylib', 'NotifyBubbles.plist', 'NFBPreferences.bundle/NFBPreferences', 'NFBPreferences.bundle/Root.plist', 'NFBPreferences.bundle/icon.png', 'NFBPreferences.bundle/icon@2x.png', 'NFBPreferences.bundle/icon@3x.png']:
        assert suffix in payload, f'Missing payload: {suffix}'
    data = subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(path)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for suffix in ['NotifyBubbles.dylib','NFBPreferences.bundle/NFBPreferences']:
            matches = [member for member in archive.getmembers() if member.name.endswith('/'+suffix) and member.isfile()]
            assert len(matches) == 1, f'Expected one binary: {suffix}'
            identities = architectures(archive.extractfile(matches[0]).read())
            assert identities == {(ARM64,0),(ARM64,2)}, f'Incorrect actual Mach-O architectures: {suffix}: {identities}'
        info = next(member for member in archive.getmembers() if member.name.endswith('NFBPreferences.bundle/Info.plist'))
        assert plistlib.loads(archive.extractfile(info).read())['CFBundleVersion'] == expected
    postinst = subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', str(path)])
    with tarfile.open(fileobj=io.BytesIO(postinst)) as control_tar:
        member = next((m for m in control_tar.getmembers() if m.name.lstrip('./') == 'postinst'), None)
        assert member is not None and member.mode & 0o7777 == 0o755, 'Keyboard cleanup postinst must have mode 0755'
    print(f'PASS: {path.name} ({architecture}{", " + scheme if scheme else ""}), tweak and preferences present')
