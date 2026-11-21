#!/usr/bin/env python3
"""Exercise production pull hooks in UIKit; not a SpringBoard/device test."""
import json, os, pathlib, plistlib, platform, subprocess, time
root=pathlib.Path(__file__).resolve().parents[1]
work=pathlib.Path(os.environ.get('RUNNER_TEMP','/tmp'))/'nfb-home-swipe-test'
app=work/'HomeSwipeTest.app';app.mkdir(parents=True,exist_ok=True)
def run(*args):return subprocess.check_output(list(args),text=True).strip()
sdk=run('xcrun','--sdk','iphonesimulator','--show-sdk-path')
arch='arm64' if platform.machine()=='arm64' else 'x86_64'
run('xcrun','--sdk','iphonesimulator','clang','-target',arch+'-apple-ios16.0-simulator','-isysroot',sdk,
    '-DNFB_HOME_SWIPE_TEST','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations',
    '-I',str(root/'Sources'),'-framework','UIKit','-framework','Foundation',
    str(root/'Sources/NFBHomeSwipeClose.m'),str(root/'Sources/NFBInterfaces.m'),
    str(root/'Tests/HomeSwipeTests.m'),'-o',str(app/'HomeSwipeTest'))
bundle='local.notifybubbles.home-swipe-tests'
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle,'CFBundleExecutable':'HomeSwipeTest',
    'CFBundleName':'HomeSwipeTest','CFBundleVersion':'1','CFBundleShortVersionString':'1.0',
    'CFBundlePackageType':'APPL','MinimumOSVersion':'16.0','LSRequiresIPhoneOS':True,
    'UIDeviceFamily':[1],'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}))
run('codesign','--force','--sign','-',str(app))
devices=json.loads(run('xcrun','simctl','list','devices','available','--json'))
candidates=[d for runtime,group in devices['devices'].items() for d in group
    if 'iOS' in runtime and d.get('isAvailable') and 'iPhone' in d['name']]
if not candidates:raise RuntimeError('No iPhone simulator available')
device=next((d for d in candidates if d['state']=='Booted'),candidates[0]);udid=device['udid']
if device['state']!='Booted':run('xcrun','simctl','boot',udid)
run('xcrun','simctl','bootstatus',udid,'-b');run('xcrun','simctl','install',udid,str(app))
container=pathlib.Path(run('xcrun','simctl','get_app_container',udid,bundle,'data'))
result=container/'Documents/home-swipe-test-result.txt';result.unlink(missing_ok=True)
run('xcrun','simctl','launch',udid,bundle)
try:
    for _ in range(60):
        if result.exists():
            text=result.read_text();assert text=='PASS',text
            print('Home swipe native callback ownership + cancellation + target binding: PASS');break
        time.sleep(1)
    else:raise TimeoutError('Home swipe UIKit fixture did not return')
finally:run('xcrun','simctl','terminate',udid,bundle)
