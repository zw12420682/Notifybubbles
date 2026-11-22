from pathlib import Path
import shutil,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
w=(r/'Sources/NFBWindowControls.m').read_text();m=(r/'Sources/NFBManager.m').read_text()
x=m.split('- (void)clearAllTapped:',1)[1].split('- (NFBActionMode)desktopActionMode',1)[0]
assert 'if (!NFBMovieOwnsDesktopSession()) [NFBSplitCoordinator.shared closeDesktop];' in x
assert x.index('NFBMovieOwnsDesktopSession') < x.index('closeCurrentWindow')
assert 'movieDesktopSession==NFBDesktopSessionIdentifier()' in w
cache=w.split('CGRect NFBSplitFrameInView',1)[1].split('BOOL NFBSplitFrameClassUnavailable',1)[0]
assert cache.index('NFBMovieValidLower(frame, root.bounds)') < cache.index('portraitRailReference = frame')
layout=w.split('CGRect lower = moviePortrait',1)[1].split('movieLowerScreen =',1)[0]
assert 'NFBMovieValidLower(reference, area)' in layout
assert layout.index('if (!NFBMovieValidLower(lower, area))') < layout.index('movieDesktopAnchor.frame = lower')
attempt=w.split('if (movieIsActive && !moviePortrait && movieDesktopAnchor.window',1)[1].split('movieDesktopSession=',1)[0]
assert attempt.index('NFBMovieValidLower') < attempt.index('movieDesktopAttempted = YES')
with tempfile.TemporaryDirectory() as tmp:
 out=str(Path(tmp)/'geometry')
 subprocess.run([shutil.which('clang') or 'cc','-std=c11','-Wall','-Wextra','-Werror','-I',str(r/'Sources'),str(r/'Tests/MovieGeometryPolicyTests.c'),'-lm','-o',out],check=True)
 subprocess.run([out],check=True)
print('PASS: split X keeps owned movie session; close geometry never enters reference/anchor/attempt state')
