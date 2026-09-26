"""Runs on the macOS builder after packaging. Fail rather than upload an empty DEB."""
import subprocess
import sys
from pathlib import Path

assert len(sys.argv) > 1, 'No DEB supplied'
for argument in sys.argv[1:]:
    path = Path(argument)
    assert path.is_file(), f'Missing package: {path}'
    architecture = subprocess.check_output(['dpkg-deb', '-f', str(path), 'Architecture'], text=True).strip()
    assert architecture == 'iphoneos-arm64e', f'Incorrect architecture: {architecture}'
    payload = subprocess.check_output(['dpkg-deb', '-c', str(path)], text=True)
    # NotifyBubblesBack is retired (see the Makefile comment), so it must not be
    # packaged any more: it would inject into every UIKit app for no gesture.
    assert 'NotifyBubblesBack.dylib' not in payload, 'Retired app-side helper is still in the DEB.'
    assert 'NotifyBubblesKeyboard.dylib' not in payload, 'Retired keyboard theme is still in the DEB.'
    for suffix in ['NotifyBubbles.dylib', 'NotifyBubbles.plist', 'NFBPreferences.bundle/NFBPreferences', 'NFBPreferences.bundle/Root.plist']:
        assert suffix in payload, f'Missing payload: {suffix}'
    postinst = subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', str(path)])
    import io, tarfile
    with tarfile.open(fileobj=io.BytesIO(postinst)) as control_tar:
        member = next((m for m in control_tar.getmembers() if m.name.lstrip('./') == 'postinst'), None)
        assert member is not None and member.mode & 0o7777 == 0o755, 'Keyboard cleanup postinst must have mode 0755'
    print(f'PASS: {path.name} ({architecture}), tweak and preferences present')
