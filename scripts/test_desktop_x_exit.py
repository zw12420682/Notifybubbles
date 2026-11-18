from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBManager.m').read_text()
a=s.index('- (void)clearAllTapped:(UITapGestureRecognizer *)gesture {');b=s.index('- (NFBActionMode)desktopActionMode',a);f=s[a:b]
a=f.index('if (NFBDesktopSplitActive())');b=f.index('if (!NFBTrollVisibleApp().length)');branch=f[a:b]
assert a<b
assert branch.index('movie:NO')<branch.index('[core closeDesktop]')
assert 'beginUserWindowOperation' in branch and 'return;' in branch
assert 'closeCurrentWindow' not in branch and '[self.store clear]' not in branch
assert 'kCFBooleanFalse' in branch
print('PASS: hosted desktop X precedes Open visibility, ends movie refill, preserves apps and notifications')
