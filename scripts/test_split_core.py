from pathlib import Path
r=Path(__file__).resolve().parents[1]
c=(r/'Sources/NFBSplitCoordinator.m').read_text();b=(r/'Sources/NFBOpenSplitBackend.m').read_text();h=(r/'Sources/NFBDesktopHost.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'NSClassFromString' not in c and 'objc_msgSend' not in c
assert 'NFBUpdateMovieMode(' not in c
assert 'NFBUpdateMovieMode(enabled)' in b
assert 'floatingWindow]' in b
assert 'movieDesktopSession==NFBDesktopSessionIdentifier()' in w
assert 'record.appliedTransform = destination' in w
assert 'record.appliedTransform = view.transform' not in w
assert 'movieHostRelinquished' in h
assert 'core.generation!=generation' in c
assert 'core.backend sceneIdentity' in c
assert 'self.enabled) return NO' in c
print('PASS: engine seam, scene-bound keyboard jobs, desktop session ownership, geometry lease only on apply, external level yield')
