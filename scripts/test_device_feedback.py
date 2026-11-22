from pathlib import Path
import shutil,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
w=(r/'Sources/NFBWindowControls.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
launch=m.split('- (void)tapped:(NFBBubble *)button {',1)[1].split('- (void)showOpenNotice:',1)[0]
keep=launch.split('if (NFBMovieOwnsDesktopSession()) {',1)[1].split('} else [NFBSplitCoordinator.shared closeDesktop];',1)[0]
assert 'beginUserWindowOperation' in keep and 'closeDesktop' not in keep and 'Parked(' not in keep
house=w.split('BOOL NFBReplaceObservedSplitWithDesktop',1)[1].split('static BOOL movieLandscape',1)[0]
assert house.index('window!=observation.portrait') < house.index('NFBReplaceMoviePaneWithAnchor')
assert house.index('NFBReplaceMoviePaneWithAnchor') < house.index('movieDesktopSession=NFBDesktopSessionIdentifier()')
assert 'if (!movieIsActive) return NFBReplaceSplitWithDesktop(window);' in house
b=(r/'Sources/NFBOpenSplitBackend.m').read_text()
assert 'return NFBReplaceObservedSplitWithDesktop(window);' in b
assert 'movieDesktopSession==NFBDesktopSessionIdentifier()' in w
cache=w.split('CGRect NFBSplitFrameInView',1)[1].split('BOOL NFBSplitFrameClassUnavailable',1)[0]
assert cache.index('NFBMovieValidLower(frame, root.bounds)') < cache.index('portraitRailReference = frame')
layout=w.split('CGRect lower=NFBMovieStandardPane(area);',1)[1].split('// Keep the desktop anchor stable.',1)[0]
assert 'CGRectGetMaxY(area)-height' in w
assert 'portraitRailReference' not in layout and 'moviePortrait' not in layout
assert layout.index('if (!NFBMovieValidLower(lower, area))') < layout.index('movieDesktopAnchor.frame = lower')
attempt=w.split('if (movieIsActive && !moviePortrait && movieDesktopAnchor.window',1)[1].split('movieDesktopSession=',1)[0]
assert attempt.index('NFBMovieValidLower') < attempt.index('movieDesktopAttempted = YES')
with tempfile.TemporaryDirectory() as tmp:
 out=str(Path(tmp)/'geometry')
 subprocess.run([shutil.which('clang') or 'cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(r/'Sources'),str(r/'Tests/MovieGeometryPolicyTests.c'),'-lm','-o',out],check=True)
 subprocess.run([out],check=True)
print('PASS: bubble launch keeps owned movie session; close geometry never enters reference/anchor/attempt state')
