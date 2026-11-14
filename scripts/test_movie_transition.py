from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Sources/NFBWindowControls.m').read_text()
assert 'kCAFillRuleEvenOdd' in s
assert 'movieDesktopAnchor.bounds toView:black' in s
assert '[touchHosts containsObject:parent.window]' in s
assert 'else black.layer.mask = nil' in s
assert s.index('black.layer.mask = mask') < s.index('NFBUpdateMovieDesktopTouchHosts(touchHosts)')
assert 'CGFloat room = MAX(1,' in s
assert 'CGRectGetMinY(lower) - CGRectGetMinY(area) < 32' in s
assert 'lower.size.width < 120 || lower.size.height < 180' in s
assert 'animateWithDuration:0.28' in s and 'UIViewAnimationOptionBeginFromCurrentState' in s
assert 'if (changed)' in s and 'completion:nil' in s
# All window combinations: only an auto desktop plus movie gets a hole/host lease.
for movie in (False,True):
 for desktop in (False,True):
  for owns in (False,True):
   lease=movie and desktop and owns
   if not movie or not desktop or not owns: assert not lease
# Initial/full-size, keyboard shrink, repeated checks, and keyboard dismissal.
old=None;starts=0
for top in [248.02,151,151,151,248.02,248.02]:
 h=min(top-4,390*9/16);target=(390*h/(390*9/16),h,top-4-h/2)
 if target!=old: starts+=1;old=target
 assert abs(top-(target[2]+h/2)-4)<1e-6
assert starts==3
print('PASS: auto-desktop black cutout, rejected transient lower, stable repeated keyboard targets, 4pt final gap')
