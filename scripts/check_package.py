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
    for suffix in ['NotifyBubblesKeyboard.dylib', 'NotifyBubblesKeyboard.plist', 'NotifyBubbles.dylib', 'NotifyBubbles.plist', 'NFBPreferences.bundle/NFBPreferences', 'NFBPreferences.bundle/Root.plist']:
        assert suffix in payload, f'Missing payload: {suffix}'
    print(f'PASS: {path.name} ({architecture}), tweak and preferences present')
