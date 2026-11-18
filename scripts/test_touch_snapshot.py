from pathlib import Path
r=Path(__file__).resolve().parents[1]
l=(r/'Sources/NFBWindowLease.m').read_text();h=(r/'Sources/NFBDesktopHost.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'identifier!=self.sessionIdentifier' in l
assert 'NSHashTable weakObjectsHashTable' in l
assert 'hit.window==host' in l
assert '[root isDescendantOfView:view]' in l
assert 'view.clipsToBounds' in l
assert 'publishTouchWindows:windows session:desktopSession' in h
assert 'current.identifier==activationSession' in h
assert 'NFBPublishMovieTouchWindows(touchRoots, NFBDesktopSessionIdentifier())' in w
assert 'sendEvent:' not in l
assert 'NFBDesktopFloatingHit(object, nil' not in h
print('PASS: touch candidates from movie observation, native same-window hit, live ancestor checks, stale-session activation rejected')

assert 'else if (mini==1' in w and '[minis addObject:view]' in w
assert '[touchHosts containsObject:mini.window]' in w
assert '[p insertSubview:mini aboveSubview:upper]' in w
assert '[r.parent insertSubview:mini belowSubview:r.next]' in w
