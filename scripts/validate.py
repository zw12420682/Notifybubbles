"""Portable structural/package checks. Behavioral tests run in macOS CI."""
from pathlib import Path
import plistlib
import re

root=Path(__file__).resolve().parents[1]
def read(path):
    return (root/path).read_text(encoding="utf-8")

control_bytes=(root/"control").read_bytes()
assert b"\r" not in control_bytes and control_bytes.endswith(b"\n")
assert not control_bytes.startswith(b"\xef\xbb\xbf")
control=dict(line.split(": ",1) for line in control_bytes.decode("utf-8").splitlines() if ": " in line)
assert control["Package"]=="local.notifybubbles"
assert control["Architecture"]=="iphoneos-arm64e"
assert re.fullmatch(r"[0-9]+(?:[.][0-9]+){2}",control["Version"])
for path in root.rglob("*.plist"):
    if not any(part.startswith(".theos") for part in path.parts):
        plistlib.loads(path.read_bytes())
info=plistlib.loads((root/"Preferences/Resources/Info.plist").read_bytes())
assert info["CFBundleVersion"]==control["Version"]
injection=plistlib.loads((root/"NotifyBubbles.plist").read_bytes())
assert injection["Filter"]["Bundles"]==["com.apple.springboard"]
prefs=plistlib.loads((root/"Preferences/Resources/Root.plist").read_bytes())
assert {item["key"] for item in prefs["items"] if "key" in item}=={
    "Enabled","ShowOnLock","ShowOnHome","ShowInApps","IconSize","IconOpacity",
    "ClosePreviousSplit","HideInScreenshots",
    "DebugLogging","HotspotAutoClose","HotspotIdleMinutes"}
print("PASS: package identity, versions, preference keys and SpringBoard-only injection")

makefile=read("Makefile")
assert "THEOS_PACKAGE_SCHEME = roothide" in makefile
assert "NFB_PACKAGE_VERSION" in makefile and "sed -n 's/^Version: //p' control" in makefile
inputs=re.search(r"^NotifyBubbles_FILES\s*=\s*(.+)$",makefile,re.M).group(1).split()
assert len(inputs)==len(set(inputs)), "Duplicate implementation in build inputs"
discovered={p.relative_to(root).as_posix() for p in (root/"Sources").glob("*.m")}
# Overlay uploads do not remove files that were moved into Legacy. These two
# retired implementations are harmless only while excluded from build inputs.
retired={"Sources/NFBAppBack.m","Sources/NFBBackRequest.m"}
assert not (set(inputs)&retired), "Retired helpers must not be compiled: " + str(sorted(set(inputs)&retired))
missing=set(inputs)-discovered
assert not missing, "Missing build sources: " + str(sorted(missing))
unbuilt=discovered-set(inputs)
if unbuilt:
    print("NOTE: source files excluded from Makefile build inputs: " + ", ".join(sorted(unbuilt)))
assert {"Sources/NFBInterfaces.m","Sources/NFBStateLedger.m","Sources/NFBDesktopHost.m"}<=set(inputs)
for name in inputs:
    assert (root/name).is_file() and not name.startswith("Legacy/")
assert "../Sources/NFBInterfaces.m" in read("Preferences/Makefile")
pending=[root/name for name in inputs]
seen=set()
while pending:
    path=pending.pop()
    if path in seen: continue
    seen.add(path)
    source=path.read_text(encoding="utf-8")
    for quoted in re.findall(r'^#(?:import|include)\s+"([^"]+)"',source,re.M):
        dependency=(path.parent/quoted).resolve()
        assert dependency.is_file(), "Missing active dependency: " + str(path.relative_to(root)) + " -> " + quoted
        pending.append(dependency)
assert (root/"layout/DEBIAN/postinst").is_file()
print("PASS: every active implementation is linked once, shared preference dependency and local imports resolve")

for relative in ["Sources/NFBOpenEdge.m","Sources/NFBWindowControls.m","Sources/NFBEdgeInspection.h","Sources/NFBRightEdgeAction.h","Sources/NFBWindowKind.h"]:
    source=read(relative)
    for forbidden in ["class_getInstanceVariable","object_getIvar","ivar_getOffset",'valueForKey:@"_targets"']:
        assert forbidden not in source, (relative,forbidden)
assert "SBDeviceApplicationSceneEntity" not in read("Sources/NFBDesktopHost.m")
print("PASS: private gesture target memory inspection and ordinary SpringBoard scene route stay excluded")

workflow=read(".github/workflows/build.yml")
tests=["StoreTests.m","TrollOpenTests.m","TransitionTests.c","InterfaceTests.m","StateLedgerTests.m"]
scripts=["validate.py","test_validator.py","test_cleanup.py","test_package_parser.py","test_desktop_simulator.py","check_package.py"]
problems=[]
for test in tests:
    if not (root/"Tests"/test).is_file(): problems.append("Missing test file: Tests/"+test)
    if test not in workflow: problems.append("Missing workflow test step for: "+test)
for script in scripts:
    if not (root/"scripts"/script).is_file(): problems.append("Missing CI script: scripts/"+script)
    if script not in workflow: problems.append("Missing workflow script step for: "+script)
simulator=read("scripts/test_desktop_simulator.py")
for dependency in ["NFBInterfaces.m","NFBStateLedger.m"]:
    if dependency not in simulator: problems.append("Old simulator build command omits: "+dependency)
blocks=re.findall(r"(?m)^ {8}run: \|\n((?: {10}[^\n]*\n|\n)+)",workflow+"\n")
for test in ["StoreTests.m","TrollOpenTests.m","InterfaceTests.m"]:
    if not any(test in block and "Sources/NFBInterfaces.m" in block for block in blocks):
        problems.append("Old Foundation test build command omits Sources/NFBInterfaces.m for: "+test)
assert not problems, "Build/test files are out of sync:\n - "+"\n - ".join(problems)+"\nReplace .github/workflows/build.yml, Tests/ and scripts/ together from the build-support patch."
print("PASS: behavioral, cleanup, ABI adapter, state restoration and UIKit tests are configured in CI")

assert "TWEAK_NAME = NotifyBubbles\n" in makefile, "Restore the SpringBoard-only Makefile; stopped keyboard target must not build"
for path in ["Sources/NFBManager.m","Sources/NFBPrivacy.m","Sources/NFBPrivacy.h","Sources/NFBDesktopHost.m"]:
    assert "NFBUpdateDesktopFreeze" not in read(path), "Retired desktop freeze logic remains: "+path
assert "FreezeDesktop" not in read("Preferences/Resources/Root.plist")
assert "KeyboardBottomEnabled" not in read("Preferences/Resources/Root.plist")
print("PASS: 0.48.52 baseline, desktop freeze removed and discontinued keyboard target excluded")
