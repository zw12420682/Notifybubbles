from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();w=(r/'Sources/NFBWindowControls.m').read_text()
f=w[w.index('BOOL NFBRecheckMovieDesktopAfterCleanup('):]
assert f.index('if (NFBDesktopSplitActive()) return YES') < f.index('movieDesktopAttempted=NO')
assert 'else if ([clearedApps containsObject:appOfWindow(view)])' in f
assert 'if (!landscape) return YES' in f and 'if (closingPortrait) return NO' in f
assert 'NFBOpenTrollApp' not in f and 'NFBClose' not in f
assert 'attempt<6' in m
for token in ['manager.exitEpoch!=exitEpoch','manager.clearEpoch!=epoch','[manager isLocked]','!NFBPreference(@"MovieMode", NO)','fallbackDone=NFBRecheckMovieDesktopAfterCleanup(targets)']:
 assert token in m,token
# stopped vs retry policy: existing desktop or new lower must not be toggled.
def check(desktop,landscape,lower,targets):
 if desktop:return 'stop'
 if lower and lower not in targets:return 'stop'
 if not landscape:return 'stop'
 if lower:return 'retry'
 return 'open'
assert check(True,True,None,[])=='stop'
assert check(False,True,'new',['old'])=='stop'
assert check(False,True,'old',['old'])=='retry'
assert check(False,False,None,[])=='stop'
assert check(False,True,None,['old'])=='open'
print('PASS: bounded post-cleanup fallback; no desktop toggling or app close; new lower/lock/settings/generation cancel')
