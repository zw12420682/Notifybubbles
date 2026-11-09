"""Regression: an unconfirmed empty snapshot must not resurrect cleared rows.
Captured on device: row creation at +0.55s, then burst removal at +1.00s.
"""
from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'Sources/NFBManager.m').read_text()
start = s.index('NSSet *set = [NSSet setWithArray:current];')
a = s.index('if (current.count == 0 && self.lastSwitcher.count > 0)', start)
b = s.index('if (++self.emptyReads >= 2)', a)
c = s.index('self.lastSwitcher = current; self.emptyReads = 0;', b)
d = s.index('[self.dismissedSwitcher intersectSet:set];', start)
assert start < a < b < c < d, 'dismissals pruned before empty snapshot was accepted'
# Model the two reads, with a layout between them.
last = ['sms', 'edge', 'photos', 'stock']
dismissed = set(last)
reads = 0
for expected in ([], []):
    current = []
    reads += 1
    if reads >= 2:
        last = current
        dismissed.intersection_update(current)
    rows = [app for app in last if app not in dismissed]
    assert rows == expected, f'cleared rows resurrected: {rows}'
assert not last and not dismissed
print('PASS: first empty read retains dismissals; confirmed empty commits list and markers together')
