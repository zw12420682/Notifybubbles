from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/NFBWidgetDetachTrace.m').read_text()
for token in ['CHUISWidgetHostViewControllerView','SBHWidgetViewController','didMoveToSuperview','willMoveToParentViewController:','removeFromParentViewController','class_addMethod','sig.numberOfArguments','getArgumentTypeAtIndex:2','NSThread.callStackSymbols','nfbDetachBudget=48']:
 assert token in s,token
for token in ['nfbOriginalViewMove(object,selector);','nfbOriginalWillParent(object,selector,parent);','nfbOriginalDidParent(object,selector,parent);','nfbOriginalRemoveParent(object,selector);']:
 assert s.count(token)==1,token
for forbidden in ['setContentOffset:', 'beginAppearanceTransition:', 'addSubview:', 'removeFromSuperview]', 'makeKeyWindow']:
 assert forbidden not in s,forbidden
assert 'if (newLockCycle || !nfbDetachArmed)' in s
assert 'NFBDebugLoggingEnabled() && NSThread.isMainThread && nfbDetachBudget' in s
print('PASS: exact classes/signature validation, subclass-only hooks, originals once, bounded debug-only stacks, no recovery mutations')
