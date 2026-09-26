"""Exercise installer cleanup against an isolated fake package database."""
from pathlib import Path
import os, subprocess, tempfile, sys
root = Path(__file__).resolve().parents[1]
shell = sys.argv[1] if len(sys.argv) > 1 else '/bin/sh'
def posix(p):
    text = str(Path(p).resolve()).replace('\\', '/')
    return '/' + text[0].lower() + text[2:] if len(text) > 1 and text[1] == ':' else text
with tempfile.TemporaryDirectory(prefix='cleanup-test-', dir=root.parent) as temp:
    tmp = Path(temp)
    folder = tmp / 'space dir/Library/MobileSubstrate/DynamicLibraries'
    folder.mkdir(parents=True)
    main = folder/'NotifyBubbles.dylib'; main.write_text('keep-main')
    retired = folder/'NotifyBubblesKeyboard.dylib'; retired.write_text('orphan')
    disabled = folder/'NotifyBubblesKeyboard.dylib.disabled'; disabled.write_text('orphan-disabled')
    protected = folder/'NotifyBubblesKeyboard.plist'; protected.write_text('another-package')
    unrelated = folder/'TrollOpenKeyboard.dylib'; unrelated.write_text('keep-trollopen')
    other = tmp/'other-bootstrap/NotifyBubblesKeyboard.dylib'; other.parent.mkdir(); other.write_text('keep-other-root')
    bindir = tmp/'bin'; bindir.mkdir()
    mock = bindir/'dpkg-query'
    mock.write_text("#!/bin/sh\ncase \"$1\" in\n-L) printf '%s\\n' \"$NFB_TEST_MAIN\" ;;\n-S) case \"$2\" in *.plist) printf 'other.package: %s\\n' \"$2\" ;; *) exit 1 ;; esac ;;\nesac\n", encoding='utf-8', newline='\n')
    mock.chmod(0o755)
    env = os.environ.copy(); env['NFB_TEST_MAIN'] = posix(main)
    command = 'PATH="$1:/usr/bin:/bin:$PATH"; export PATH; sh "$2" "$3"'
    args = [shell, '-c', command, 'test', posix(bindir), posix(root/'layout/DEBIAN/postinst')]
    subprocess.run(args+['abort-upgrade'],env=env,check=True,capture_output=True,text=True)
    assert retired.exists(), 'Non-configure invocation must not delete'
    result = subprocess.run(args+['configure'],env=env,check=True,capture_output=True,text=True)
    assert not retired.exists() and not disabled.exists(), result.stdout+result.stderr
    for path, value in [(main,'keep-main'),(protected,'another-package'),(unrelated,'keep-trollopen'),(other,'keep-other-root')]:
        assert path.read_text() == value, path
    subprocess.run(args+['configure'],env=env,check=True,capture_output=True,text=True)
print('PASS: orphan cleanup, disabled file, foreign ownership, unrelated files, bootstrap scope and repeated install')
