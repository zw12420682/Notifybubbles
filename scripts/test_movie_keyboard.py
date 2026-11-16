from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text();c=(r/'Sources/NFBSplitCoordinator.m').read_text()
a=m.index('if (keyboardUp != wasUp)');b=m.index('if (!keyboardUp && wasUp)',a)
assert '[core scheduleMovieKeyboardChecks]' in m[a:b]
assert 'NFBRecheckSplitPlacement' not in m[a:b]
assert '@[@0.12,@0.32,@0.65]' in c
assert 'core.generation!=generation' in c
assert 'sceneIdentity] isEqualToString:scene' in c
assert '!self.enabled || self.locked || !self.movie || !self.keyboard' in c
print('PASS: unified keyboard scheduling, bounded checks, generation and backend scene validation')
