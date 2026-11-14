from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBManager.m').read_text()
a=s.index('- (void)tapped:(NFBBubble *)button {'); b=s.index('NFBCloseDesktopSplit();',a)
entry=s[a:b]
assert 'NFBPreference(@"MovieMode", NO)' in entry
assert 'NFBTrollVisibleApp()' in entry and 'NFBSplitAttachmentApp()' in entry
assert 'current app tap ignored' in entry and 'return;' in entry
assert entry.index('current app tap ignored') < entry.index('[self touchColumn]')
w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'anchor == movieDesktopAnchor ? portraitCornerRadius : NAN' in w
h=(r/'Sources/NFBDesktopHost.m').read_text()
assert 'panel.clipsToBounds = YES' in h
assert 'isfinite(movieRadius) ? MAX(0, movieRadius) : 14' in h
assert 'session!=self || self.restoring || self.startedHome || self.pendingApp.length' in h
assert 'NFBLogWidgetHosts(sample.desktop, 0, &budget)' in h
print('PASS: movie current tap blocked before side effects; movie desktop corners; widget strategy unchanged')
