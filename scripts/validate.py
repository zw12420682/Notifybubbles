"""Portable structural/package checks. Behavioral tests run in macOS CI.

Usage: python3 scripts/validate.py [--scheme rootless|roothide]
With no argument every supported packaging scheme is checked.
"""
from pathlib import Path
import plistlib
import re
import sys

root=Path(__file__).resolve().parents[1]
SCHEMES={"rootless":"iphoneos-arm64","roothide":"iphoneos-arm64e"}
DEFAULT_SCHEME="rootless"
scheme_argument=None
arguments=sys.argv[1:]
while arguments:
    argument=arguments.pop(0)
    if argument in ("--scheme","-s"):
        assert arguments, "--scheme needs a value"
        scheme_argument=arguments.pop(0)
    elif argument.startswith("--scheme="):
        scheme_argument=argument.split("=",1)[1]
    else:
        raise SystemExit("Unknown argument: "+argument+" (use --scheme rootless|roothide)")
if scheme_argument is not None:
    assert scheme_argument in SCHEMES, "Unknown scheme: "+scheme_argument
schemes=[scheme_argument] if scheme_argument else list(SCHEMES)
def read(path):
    return (root/path).read_text(encoding="utf-8")

control_bytes=(root/"control").read_bytes()
assert b"\r" not in control_bytes and control_bytes.endswith(b"\n")
assert not control_bytes.startswith(b"\xef\xbb\xbf")
control=dict(line.split(": ",1) for line in control_bytes.decode("utf-8").splitlines() if ": " in line)
assert control["Package"]=="local.notifybubbles"
# `control` carries the default (rootless) identity; per-scheme files only swap
# the Architecture field that Theos stages before packaging.
assert control["Architecture"]==SCHEMES[DEFAULT_SCHEME]
assert re.fullmatch(r"[0-9]+(?:[.][0-9]+){2}",control["Version"])
assert control["Depends"]=="firmware (>= 16.0), firmware (<< 17.0), mobilesubstrate, preferenceloader"
for scheme,architecture in SCHEMES.items():
    fragment_bytes=(root/("control."+scheme)).read_bytes()
    assert b"\r" not in fragment_bytes and fragment_bytes.endswith(b"\n"), "control."+scheme
    fragment=dict(line.split(": ",1) for line in fragment_bytes.decode("utf-8").splitlines() if ": " in line)
    assert fragment=={"Architecture":architecture}, ("control."+scheme, fragment)
    assert control["Architecture"]!=architecture or scheme==DEFAULT_SCHEME
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
    "HalfHiddenUnreadOpaque",
    "ClosePreviousSplit","HideInScreenshots",
    "DebugLogging","HotspotAutoClose","HotspotIdleMinutes"}
print("PASS: package identity, versions, preference keys and SpringBoard-only injection")
print("PASS: scheme-aware control fragments: "+", ".join("control."+s+" -> "+a for s,a in SCHEMES.items())+" (default "+DEFAULT_SCHEME+")")

makefile=read("Makefile")
# The scheme must be switchable from the command line/environment instead of
# being hard-coded: a weak `?=`/empty-guard default plus the scheme->control
# mapping is what makes rootless and roothide buildable from one tree.
scheme_declarations=re.findall(r"(?m)^THEOS_PACKAGE_SCHEME\s*([?:]?=)",makefile)
assert scheme_declarations, "Makefile must declare THEOS_PACKAGE_SCHEME (weak so the command line can override)"
assert all(fragment in ("?=","=",":=") for fragment in scheme_declarations), \
    "THEOS_PACKAGE_SCHEME defaults must be weak (?= or guarded =) so -e/command line can override them"
scheme_guard=re.search(r"(?ms)^ifeq \(\$\(strip \$\(THEOS_PACKAGE_SCHEME\)\),\)\n(.*?)^endif",makefile)
assert scheme_guard, "Makefile must default the scheme only when it is unset (ifeq ($(strip $(THEOS_PACKAGE_SCHEME)),))"
guarded_default=re.search(r"(?m)^THEOS_PACKAGE_SCHEME\s*(\?=|:=)\s*rootless\s*$",scheme_guard.group(1))
assert guarded_default, "Makefile default scheme must be rootless and stay overridable from the command line"
assert "NFB_SCHEME_CONTROL = control.$(THEOS_PACKAGE_SCHEME)" in makefile
assert "rootless roothide" in makefile and "$(error Unsupported THEOS_PACKAGE_SCHEME" in makefile
assert "ARCHS = arm64 arm64e" in makefile and "TARGET = iphone:clang:16.5:16.0" in makefile
# Both packaging flavours must stay documented (README) and wired into CI.
workflow_text=read(".github/workflows/build.yml")
for scheme in SCHEMES:
    assert scheme in workflow_text and "THEOS_PACKAGE_SCHEME=" in workflow_text, "CI must build scheme "+scheme
    assert "NotifyBubbles-"+scheme in workflow_text, "CI artifact for "+scheme+" must be named NotifyBubbles-"+scheme
assert "--scheme" in workflow_text, "CI must pin the expected scheme in check_package.py"
assert not re.search(r"uses: actions/(checkout|upload-artifact|cache)@v[0-9]+\.[0-9]", workflow_text), \
    "Pin stable major action versions (checkout@v4, upload-artifact@v4, cache@v4)"
readme=read("README.md")
for token in ["rootless","roothide","THEOS_PACKAGE_SCHEME","/var/jb","RootHide"]:
    assert token in readme, "README must document "+token
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
scripts=["validate.py","test_validator.py","test_cleanup.py","test_package_parser.py","test_desktop_simulator.py","check_package.py","test_scheme.py"]
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

for script in (root/"scripts").glob("*.py"):
    compile(script.read_bytes(),str(script),"exec")
print("PASS: every project Python script parses before build/package")
