from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'Sources/NFBDesktopHost.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
f=h[h.index('BOOL NFBReplaceSplitWithDesktop('):]
assert 'closeWindowWithoutTerminatingProcessWithoutAnimation' in f
assert 'NFBTerminate' not in f and 'kill(' not in f
assert f.index('NFBShowDesktopInSplit(window)') < f.index('active.independentAnchor=proxy') < f.index('invokeWithTarget:window')
assert 'active.anchor=proxy' in f
assert '[NFBSplitCoordinator.shared replaceWindowWithDesktop:target]' in m
assert '[self.independentAnchor removeFromSuperview]' in h
print('PASS: exact instance close without process termination; independent desktop anchor and cleanup')
