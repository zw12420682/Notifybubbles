from pathlib import Path
r=Path(__file__).resolve().parents[1]
m=(r/'Sources/NFBManager.m').read_text()
w=(r/'Sources/NFBWindowControls.m').read_text()
assert 'movieFit' not in m and 'CGFloat movieSide' not in m
assert 'BOOL hideForPosition = floatingApp.length && !atBottomLeft;' in m
assert 'plan.favoritesVisible =' not in m
assert 'NFBRailPlan plan = NFBPlanRail(' in m
assert 'self.movieDoubleTap.numberOfTapsRequired = 2' in m
assert 'if (!NFBDesktopSplitActive()) movieOwnsDesktop = NFBShowDesktopInSplit' in w
start=w.index('static void movieRestore('); end=w.index('BOOL NFBUpdateMovieMode(', start)
restore=w[start:end]
assert restore.index('if (record.moved && sameOwner)') < restore.index('view.transform = record.transform')
assert 'CGRectGetMinY(lower)-CGRectGetMinY(area)-movieGap' in w
print('PASS: original rail plan/position gate; untouched portrait restoration; movie actions and top fit retained')
