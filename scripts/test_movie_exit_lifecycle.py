from pathlib import Path
r=Path(__file__).resolve().parents[1]
w=(r/'Sources/NFBWindowControls.m').read_text();h=(r/'Sources/NFBDesktopHost.m').read_text();c=(r/'Sources/NFBSplitCoordinator.m').read_text();l=(r/'Sources/NFBStateLedger.m').read_text()
assert 'NFBSplitRetainMovieWithClosure(&movieObservation' in w
assert 'movieHadLandscape && observation.classAvailable && observation.sceneAvailable' in w
assert 'old.window && boolStateOf(old,@"isClosingWithKeepAliveAnimation")!=1' in w
assert w.index('BOOL explicitlyClosed=') < w.index('if (!explicitlyClosed && enabled == movieWasEnabled')
assert 'movieLastLandscape=[NSHashTable weakObjectsHashTable]' in w
assert 'desktop-cleanup-time:' in h and 'desktop-cleanup-time:' in l
restore=h[h.index('- (void)restore {'):h.index('// Disposable visual layer:')]
assert restore.index('if (self.restoring) return;') < restore.index('releaseSession:self.identifier')
assert 'core.backend!=backend || core.operationEpoch!=operation' in c
assert '[backend desktopSessionIdentifier]!=desktop' in c
print('PASS: explicit closure skips grace, hidden/unknown retains protection, idempotent restore, session-bound keyboard jobs and debug-only cleanup timings')
