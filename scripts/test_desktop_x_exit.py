from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBManager.m').read_text()
a=s.index('- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {');b=s.index('- (NFBActionMode)desktopActionMode',a);f=s[a:b]
a=f.index('if (NFBDesktopSplitActive())');b=f.index('if (!NFBTrollVisibleApp().length)');branch=f[a:b]
assert a<b
assert 'beginUserWindowOperation' in branch and 'return;' in branch
assert 'NFBCloseMovieDesktopWithTransition(NFBDesktopSessionIdentifier())' in branch
assert 'MovieMode' not in branch and 'updateEnabled:' not in branch
assert 'closeCurrentWindow' not in branch and '[self.store clear]' not in branch
print('PASS: hosted desktop X returns only desktop, preserves movie mode/Open app, and avoids notification clearing')
