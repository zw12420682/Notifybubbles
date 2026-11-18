from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();b=(r/'Sources/NFBOpenSplitBackend.m').read_text();c=(r/'Sources/NFBSplitCoordinator.m').read_text()
f=m[m.index('- (void)desktopActionUpSwiped:'):m.index('- (void)desktopActionSwiped:',m.index('- (void)desktopActionUpSwiped:'))]
for token in ['UISwipeGestureRecognizerDirectionUp','NFBDesktopSplitActive()','target!=NFBDesktopActionWindow()','rotateWindow:target']:assert token in f
assert '[self.movieDoubleTap requireGestureRecognizerToFail:self.desktopActionUpSwipe]' in m
assert '[self.desktopActionTap requireGestureRecognizerToFail:self.desktopActionUpSwipe]' in m
assert 'NSSelectorFromString(@"rotateButtonTapped")' in b
assert 'sig.numberOfArguments!=2' in b
assert 'strcmp(sig.methodReturnType,@encode(void))' in b
assert '((void (*)(id,SEL))objc_msgSend)(window,rotate)' in b
assert '[self.backend desktopActive]' in c
print('PASS: house-only up swipe, exact live app target, desktop rejection, native Open rotate ABI, tap arbitration retained')
