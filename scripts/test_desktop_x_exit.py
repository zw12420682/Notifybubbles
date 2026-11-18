from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBManager.m').read_text()
a=s.index('- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {');b=s.index('- (NFBActionMode)desktopActionMode',a);f=s[a:b]
a=f.index('if (NFBDesktopSplitActive())');b=f.index('if (!NFBTrollVisibleApp().length)');branch=f[a:b]
assert a<b
assert branch.index('observation.landscapeWindows.count!=1') < branch.index('NFBCloseObservedLandscape(')
assert branch.index('NFBCloseObservedLandscape(') < branch.index('NFBCloseMovieDesktopWithTransition(')
assert 'MovieMode' in branch and 'MovieMode",NO' in branch
assert 'beginUserWindowOperation' in branch and 'return;' in branch
assert 'closeCurrentWindow' not in branch and '[self.store clear]' not in branch
c=(Path(__file__).resolve().parents[1]/'Sources/NFBCloseObservedLandscape.inc').read_text()
assert 'movieDesktopAttempted=YES' in c and 'movieLandscape(target)' in c
print('PASS: X requires one exact landscape close before desktop return and suppresses refill')
