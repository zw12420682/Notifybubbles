#!/usr/bin/env python3
from pathlib import Path
import shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/NFBHomeSwipeClose.m').read_text()
w=(root/'Sources/NFBWindowControls.m').read_text()
m=(root/'Sources/NFBManager.m').read_text()
t=(root/'Sources/Tweak.m').read_text()
assert 'NFBConfigureHomeSwipeClose(self.enabled)' in m
assert 'NFBInstallHomeSwipeClose();' in t
assert 'Sources/NFBHomeSwipeClose.m' in (root/'Makefile').read_text()
for phase in ('Began','Updated','Ended','Canceled'):
    assert f'grabberTongue{phase}Pulling:withDistance:andVelocity:andGesture:' in s
assert s.index('sig.numberOfArguments != 6')<s.index('MSHookMessageEx(cls, selector')
for guard in ('deckGrabberTongue','homeGestureBottomEdgeRecognizer','edgePullGestureRecognizer',
              'session.configuration != NFBHomeSwipeConfiguration','session.operationEpoch != NFBSplitCoordinator.shared.operationEpoch',
              'session.invalid = YES','session.finished = YES','session.tongue != tongue',
              'NFBHomeSwipeCanCapture','NFBHomeSwipeCanFinish'):
    assert guard in s,guard
strict=w.split('BOOL NFBCloseHomeSwipeWindow(UIView *window) {',1)[1].split('BOOL NFBCloseCurrentSplit(void) {',1)[0]
assert 'NFBHomeSwipeCloseWindow() != window' in strict
controls=w
select=controls.split('UIView *NFBHomeSwipeCloseWindow(void)',1)[1].split('BOOL NFBCloseHomeSwipeWindow',1)[0]
assert 'window = observation.portrait' in select and 'observation.landscapeWindows containsObject:window' in select
assert 'NFBExpandedWindowKind(' in select and 'observation.windows.firstObject' not in select
assert 'NFBDispatchRightEdgeTap(window, tap)' in strict
assert 'beginUserWindowOperation' in strict
for forbidden in ('closeCurrentFloatingWindow','closeWindowWithoutTerminating','NFBCloseCurrentSplit(',
                  'terminate','kill(','closeDesktop','dispatch_after','insertSubview'):
    assert forbidden not in strict,forbidden
for forbidden in ('setEnabled:','UIWindow alloc','addGestureRecognizer:','_handleSwitcherPanGestureEnded:',
                  'performSelector:','closeCurrentWindow]','dispatch_after','NFBCloseCurrentSplit('):
    assert forbidden not in s,forbidden
compiler=shutil.which('clang') or shutil.which('cc')
assert compiler,'C compiler required'
with tempfile.TemporaryDirectory() as directory:
    binary=str(Path(directory)/'home-swipe-policy')
    subprocess.run([compiler,'-std=c11','-Wall','-Wextra','-Werror','-I',str(root/'Sources'),
                    str(root/'Tests/HomeSwipePolicyTests.c'),'-lm','-o',binary],check=True)
    subprocess.run([binary],check=True)
print('Home swipe ownership and exact native target guards PASS')
