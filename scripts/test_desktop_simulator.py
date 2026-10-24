#!/usr/bin/env python3
"""Run production desktop hosting against real UIKit views in an iOS simulator.
Private desktop fixtures test the transplant, not SpringBoard device compatibility.
"""
import hashlib, json, os, pathlib, plistlib, platform, subprocess, time
root=pathlib.Path(__file__).resolve().parents[1]
print("Desktop simulator touch-fixture-v2", flush=True)
for relative in ("Tests/DesktopHostTests.m", "Sources/NFBDesktopHost.m"):
    print(relative+" sha256="+hashlib.sha256((root/relative).read_bytes()).hexdigest(), flush=True)
work=pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp"))/"nfb-desktop-test"
app=work/"DesktopHostTest.app"; app.mkdir(parents=True,exist_ok=True)
def run(*args):
    return subprocess.check_output(list(args),text=True).strip()
sdk=run("xcrun","--sdk","iphonesimulator","--show-sdk-path")
arch="arm64" if platform.machine()=="arm64" else "x86_64"
run("xcrun","--sdk","iphonesimulator","clang","-target",arch+"-apple-ios16.0-simulator", "-isysroot",sdk,
    "-DNFB_DESKTOP_SIM_TEST","-fobjc-arc","-fblocks","-Wall","-Wextra","-Werror","-Wno-deprecated-declarations","-I",str(root/"Sources"),
    "-framework","UIKit","-framework","Foundation","-framework","QuartzCore","-framework","CoreGraphics",
    str(root/"Sources/NFBDesktopHost.m"),str(root/"Sources/NFBStateLedger.m"),str(root/"Sources/NFBInterfaces.m"),str(root/"Sources/NFBDebugLog.m"),str(root/"Tests/DesktopHostTests.m"),
    "-o",str(app/"DesktopHostTest"))
(app/"Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier":"local.notifybubbles.desktop-tests",
    "CFBundleExecutable":"DesktopHostTest","CFBundleName":"DesktopHostTest","CFBundleVersion":"1",
    "CFBundleShortVersionString":"1.0","CFBundlePackageType":"APPL","MinimumOSVersion":"16.0",
    "LSRequiresIPhoneOS":True,"UIDeviceFamily":[1],"UILaunchScreen":{},
    "UISupportedInterfaceOrientations":["UIInterfaceOrientationPortrait"]}))
run("codesign","--force","--sign","-",str(app))
devices=json.loads(run("xcrun","simctl","list","devices","available","--json"))
candidates=[d for runtime, group in devices["devices"].items() for d in group
    if "iOS" in runtime and d.get("isAvailable") and "iPhone" in d["name"]]
if not candidates: raise RuntimeError("No available iPhone simulator")
device=next((d for d in candidates if d["state"]=="Booted"),candidates[0]); udid=device["udid"]
if device["state"]!="Booted": run("xcrun","simctl","boot",udid)
run("xcrun","simctl","bootstatus",udid,"-b")
run("xcrun","simctl","install",udid,str(app))
container=pathlib.Path(run("xcrun","simctl","get_app_container",udid,"local.notifybubbles.desktop-tests","data"))
result=container/"Documents/desktop-test-result.txt"
result.unlink(missing_ok=True)
run("xcrun","simctl","launch",udid,"local.notifybubbles.desktop-tests")
try:
    for _ in range(60):
        if result.exists():
            text=result.read_text(); print(text); assert text=="PASS",text
            break
        time.sleep(1)
    else: raise TimeoutError("Desktop UIKit test did not return a result")
finally:
    run("xcrun","simctl","terminate",udid,"local.notifybubbles.desktop-tests")
