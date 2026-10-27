#!/usr/bin/env python3
"""Compiles and runs every portable test with -Werror, on any host.

CI does the same thing with clang and Apple frameworks; this script is the local
(iSH/Alpine) and CI-safe equivalent so a change to a header or a policy test is
verified with the real compiler, not by reading it:

    python3 scripts/test_policies.py

Steps:
  1. Tests/PolicyTests.c against the policy headers the manager includes
     (layout animation, burst ordering, favorite drag clock, latest pending rail
     metric, same-round probe reuse).
  2. Tests/RailLayoutTests.m in its portable mode (NFB_RAIL_PORT) against the
     same plan headers the tweak lays out from, using Tests/NFBPortableShim.h for
     the CoreGraphics types the host lacks.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
cc = shutil.which("clang") or shutil.which("cc") or shutil.which("gcc")
if not cc:
    print("SKIP: no C compiler, policy tests not exercised")
    raise SystemExit(0)

steps = [
    ("policy tests", [cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-ISources",
                      "Tests/PolicyTests.c", "-lm", "-o", "{out}/policy"], ""),
    ("rail layout (portable)", [cc, "-std=c11", "-DNFB_RAIL_PORT=1", "-Wall", "-Wextra", "-Werror",
                                "-ISources", "-ITests", "-include", "Tests/NFBPortableShim.h",
                                "Tests/RailLayoutTests.m", "-lm", "-o", "{out}/rail"], ""),
]

failures = 0
with tempfile.TemporaryDirectory(prefix="nfb-policies-") as directory:
    for name, command, _ in steps:
        binary = None
        build = [part.format(out=directory) for part in command]
        result = subprocess.run(build, cwd=root, capture_output=True, text=True)
        if result.returncode != 0:
            failures += 1
            print("FAIL: %s did not build" % name)
            print(result.stderr.strip()[:4000])
            continue
        binary = build[-1]
        run = subprocess.run([binary], cwd=root, capture_output=True, text=True)
        sys.stdout.write(run.stdout)
        sys.stdout.write(run.stderr)
        if run.returncode != 0:
            failures += 1
            print("FAIL: %s exited %d" % (name, run.returncode))

if failures:
    print("FAIL: portable tests")
    raise SystemExit(1)
print("PASS: portable policy + rail tests")
