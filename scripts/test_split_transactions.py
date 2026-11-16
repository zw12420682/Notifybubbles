from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'Sources/NFBDesktopHost.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'self.mutationPhase != NFBDesktopMutationActive' in h
assert 'self.mutationPhase=NFBDesktopMutationRestoring' in h
assert 'self.mutationPhase=NFBDesktopMutationFinished' in h
assert h.index('NFBDesktopTestCheckpoint(3)') < h.index('next.mutationPhase=NFBDesktopMutationActive')
assert 'NFBDesktopTestCheckpoint(1)' in h and 'NFBDesktopTestCheckpoint(2)' in h
assert '#ifdef NFB_DESKTOP_SIM_TEST' in h
assert 'NFBSplitRetainMovieWithClosure(&movieObservation' in w
assert w.index('if (enabled && !landscape && retained)') < w.index('movieIsActive = enabled && landscape')
fixture=(r/'Tests/DesktopHostTests.m').read_text()
assert 'fault<=3' in fixture
assert 'failure rollback returns desktop to original parent' in fixture
print('PASS: explicit desktop transaction phases, commit-last, three simulator fault points; bounded movie snapshot retention')
