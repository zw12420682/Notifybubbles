from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
a=m.index('- (void)updatePrivacy {');b=m.index('// Coalesced entry',a)
f=m[a:b]
assert f.index('NFBObserveMovieLockState') < f.index('NFBUpdateDesktopSplit(NO)')
f=w[w.index('void NFBObserveMovieLockState('):]
assert 'movieResumePending = movieIsActive' in f
assert '[NSHashTable weakObjectsHashTable]' in f
assert '@[@0.15, @0.45, @0.9, @1.5]' in f
assert 'epoch != movieResumeEpoch' in f
assert 'NFBCheckedBool(manager,@"isUILocked",YES)' in f
assert 'CFSTR("MovieMode")' in f and 'CFSTR("Enabled")' in f
for forbidden in ('NFBOpenTrollApp(', 'makeKeyAndVisible','setHidden:', 'setMiniWindow'):
 assert forbidden not in f
assert 'if (usable)' in f
assert 'movieReadAt=0' in f
assert 'movieResumePending=NO;' in f
print('PASS: movie-only weak capture, bounded unlock refit, lock/settings/epoch guards, no forced unminimize or launch')
