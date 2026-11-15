from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBArcOverlay.h').read_text()
m=(r/'Sources/NFBManager.m').read_text()
for x in ['WatchMenuView','TOJBW0','TrollOpenJB.dylib','depth>12','budget=128','nfbArcRelinquished',
          'fabs(window.windowLevel-nfbArcAppliedLevel)<0.01','CGFloat target=2002',
          'NFBRestoreArcOverlay(); return;', 'view.layer.opacity<0.01']:
 assert x in s,x
for x in ['makeKey','hitTest:', 'setHidden:', 'addGestureRecognizer:', 'setContentOffset:', 'transform=']:
 assert x not in s,x
assert 'NFBUpdateArcOverlay(self.enabled && ![self isLocked])' in m
# Policy scenarios: hidden menu, normal/movie open, close, lock/disable, external
# ownership, elevated original, and replacement window. No geometry is touched.
class Window:
 def __init__(self,level): self.level=level
class Policy:
 def __init__(self): self.w=None;self.owns=False;self.yielded=False
 def restore(self):
  if self.w and self.owns and abs(self.w.level-self.applied)<.01: self.w.level=self.original
  self.w=None;self.owns=False;self.yielded=False
 def update(self,w,enabled=True,target=2002):
  if not enabled: self.restore();return
  if w is not self.w: self.restore();self.w=w
  if w is None:return
  if self.owns and abs(w.level-self.applied)>=.01:self.owns=False;self.yielded=True
  if self.yielded:return
  if not self.owns:
   if w.level>=target:return
   self.original=w.level;self.applied=target;self.owns=True;w.level=target
  elif target>self.applied:self.applied=target;w.level=target
for enabled_end in [True,False]:
 p=Policy();w=Window(46);p.update(None);assert w.level==46
 p.update(w);assert w.level>max(2001,1002,1001)
 p.update(w);assert p.original==46
 p.update(None if enabled_end else w,enabled_end);assert w.level==46
p=Policy();w=Window(46);p.update(w);w.level=77;p.update(w);assert w.level==77
p.update(w);assert w.level==77;p.update(None);assert w.level==77
p.update(w);assert w.level==2002;p.update(None);assert w.level==77
p=Policy();a=Window(46);b=Window(47);p.update(a);p.update(b);assert a.level==46 and b.level==2002
p.restore();assert b.level==47
p=Policy();w=Window(3000);p.update(w);p.restore();assert w.level==3000
p=Policy();w=Window(46);p.update(w);p.update(w,target=2005);assert w.level==2005
p.restore();assert w.level==46
print('PASS: ARC scoped identity, visible-menu only, movie ordering, original restoration, external ownership, disable/lock, replacement, no hit-test changes')
