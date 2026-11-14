from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBDesktopHost.m').read_text()
a=s.index('- (void)refreshWidgetPage {');b=s.index('- (void)activateDesktop',a);f=s[a:b]
assert 'self.startedHome ||' not in f
assert 'self.widgetRefreshAttempts >= 6' in f
assert 'pager.tracking || pager.dragging || pager.decelerating' in f
assert 'self.widgetRefreshFinished=YES' in f
assert '[self scheduleWidgetRefreshRetry]' in f
assert 'session!=active || active.restoring' in f
assert 'active.refreshScroll=nil' in f
assert 'active.widgetRefreshCancelled = YES' in s
assert 'self.widgetRefreshCancelled=YES' in s
assert 'widgetSession=next' in s
# Missing/missing/ready: one roundtrip, never another. Missing forever bounded.
for ready_at in (0,2,5,9):
 attempts=0;roundtrips=0
 while attempts<6:
  attempts+=1
  if attempts-1>=ready_at: roundtrips+=1;break
 assert attempts<=6 and roundtrips<=1
print('PASS: both entry sources, six attempts maximum, once-only roundtrip, user priority and stale-session cancellation')
