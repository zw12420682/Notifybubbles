from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 exe=str(Path(d)/'observation')
 subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-I',str(r/'Sources'),str(r/'Tests/SplitObservationTests.c'),'-o',exe],check=True)
 subprocess.run([exe],check=True)
