"""Runs on the macOS builder after packaging. Fail rather than upload an empty DEB."""
import subprocess
import sys
from pathlib import Path
import io, tarfile, plistlib
from macho import architectures, ARM64

assert len(sys.argv) > 1, 'No DEB supplied'
for argument in sys.argv[1:]:
    path = Path(argument)
    assert path.is_file(), f'Missing package: {path}'
    expected = dict(line.split(': ',1) for line in (Path(__file__).resolve().parents[1]/'control').read_text().splitlines() if ': ' in line)['Version']
    version = subprocess.check_output(['dpkg-deb','-f',str(path),'Version'],text=True).strip()
    assert version == expected, f'Incorrect package version: {version}'
    architecture = subprocess.check_output(['dpkg-deb', '-f', str(path), 'Architecture'], text=True).strip()
    assert architecture == 'iphoneos-arm64e', f'Incorrect architecture: {architecture}'
    payload = subprocess.check_output(['dpkg-deb', '-c', str(path)], text=True)
    assert 'NotifyBubblesBack.dylib' not in payload, 'Retired return helper still packaged.'
    assert 'NotifyBubblesBack.plist' not in payload, 'Retired return filter still packaged.'
    assert 'NotifyBubblesKeyboard.dylib' not in payload, 'Retired keyboard theme is still in the DEB.'
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
    import io, tarfile
    with tarfile.open(fileobj=io.BytesIO(postinst)) as control_tar:
        member = next((m for m in control_tar.getmembers() if m.name.lstrip('./') == 'postinst'), None)
        assert member is not None and member.mode & 0o7777 == 0o755, 'Keyboard cleanup postinst must have mode 0755'
    print(f'PASS: {path.name} ({architecture}), tweak and preferences present')
