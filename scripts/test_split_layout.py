from pathlib import Path
import subprocess, tempfile
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 exe=str(Path(d)/'split-layout')
 subprocess.run(['clang','-x','c','-std=c11','-Wall','-Wextra','-Werror','-I',str(r/'Sources'),str(r/'Tests/SplitLayoutTests.c'),'-lm','-o',exe],check=True)
 subprocess.run([exe],check=True)
