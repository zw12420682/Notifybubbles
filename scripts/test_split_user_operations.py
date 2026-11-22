from pathlib import Path
r=Path(__file__).resolve().parents[1]
c=(r/'Sources/NFBSplitCoordinator.m').read_text();m=(r/'Sources/NFBManager.m').read_text();h=(r/'Sources/NFBDesktopHost.m').read_text();b=(r/'Sources/NFBOpenSplitBackend.m').read_text()
a=c.index('- (void)beginUserWindowOperation {');f=c[a:c.index('- (BOOL)installBackend:',a)]
for text in ['self.generation++','self.operationEpoch++','self.cleanupEpoch++','self.snapshot=nil','cancelReturnTransition']:assert text in f
assert '[NFBSplitCoordinator.shared fullscreenCurrentWindow]' in m
assert 'if (!NFBCloseCurrentSplit())' not in m
assert 'if (!NFBFullscreenCurrentFloatingWindow())' not in m
assert h.index('[NFBSplitCoordinator.shared beginUserWindowOperation]') < h.index('active.pendingApp=bundle')
assert 'NFBUpdateDesktopReturnTransition(NO)' in b
assert 'return NFBCloseCurrentSplit()' in b
assert 'return NFBFullscreenCurrentFloatingWindow()' in b
print('PASS: close/fullscreen/desktop launch invalidate old tasks and visual cover through shared core; Open actions retained')
