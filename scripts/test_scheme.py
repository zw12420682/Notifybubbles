#!/usr/bin/env python3
"""Offline check of the scheme switch without a real Theos toolchain.

A stub $(THEOS) provides just enough of makefiles/ for the real Makefile to be
parsed by GNU make (so the rootless default, the command line/environment
override and the unsupported-scheme guard are really exercised), and the real
before-package recipe is executed against a fake staging directory for each
scheme. No clang, no SDK, no network.
"""
from pathlib import Path
import os, re, shutil, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
make = shutil.which('make')
if not make:
    print('SKIP: GNU make not installed, scheme switch not exercised')
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix='nfb-scheme-') as directory:
    work = Path(directory) / 'project'
    work.mkdir()
    for name in ['Makefile', 'control', 'control.rootless', 'control.roothide']:
        shutil.copy2(root / name, work / name)
    (work / 'layout/DEBIAN').mkdir(parents=True)
    (work / 'layout/DEBIAN/postinst').write_text('#!/bin/sh\nexit 0\n')
    (work / 'Sources').mkdir()
    (work / 'Preferences').mkdir()
    (work / 'Preferences/Makefile').write_text('')

    theos = Path(directory) / 'theos'
    (theos / 'makefiles').mkdir(parents=True)
    (theos / 'makefiles/common.mk').write_text('THEOS_MAKE_PATH ?= $(THEOS)/makefiles\n')
    for name in ['tweak.mk', 'bundle.mk', 'instance.mk']:
        (theos / 'makefiles' / name).write_text('')
    # Stand-in aggregate.mk: provides the probe target and a neutral before-package.
    (theos / 'makefiles/aggregate.mk').write_text(
        'before-package:: ; @:\n'
        '.PHONY: before-package\n'
        'probe::\n'
        '\t@echo "scheme=$(THEOS_PACKAGE_SCHEME)"\n'
        '\t@echo "control=$(NFB_SCHEME_CONTROL)"\n')

    def run(targets, variables=(), extra_env=None):
        env = dict(os.environ, THEOS=str(theos))
        env.update(extra_env or {})
        return subprocess.run([make, '-s', '-C', str(work)] + list(targets) + list(variables),
                              env=env, capture_output=True, text=True)

    # 1. nothing on the command line -> rootless
    result = run(['probe'])
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'scheme=rootless' in result.stdout and 'control=control.rootless' in result.stdout, result.stdout

    # 2. command line and environment overrides both win
    result = run(['probe'], ['THEOS_PACKAGE_SCHEME=roothide'])
    assert 'scheme=roothide' in result.stdout and 'control=control.roothide' in result.stdout, result.stdout
    result = run(['probe'], extra_env={'THEOS_PACKAGE_SCHEME': 'roothide'})
    assert 'scheme=roothide' in result.stdout, result.stdout + result.stderr

    # 3. an unsupported scheme fails loudly instead of shipping a wrong DEB
    result = run(['probe'], ['THEOS_PACKAGE_SCHEME=rootful'])
    assert result.returncode != 0 and 'Unsupported THEOS_PACKAGE_SCHEME' in result.stderr, result.stdout + result.stderr

    # 4. the real before-package recipe stages the right Architecture and a 0755 postinst
    recipe = re.search(r'(?ms)^before-package::\n((?:\t.*\n)+)', (work / 'Makefile').read_text()).group(1)
    lines = [line[1:] for line in recipe.splitlines()]
    # Join backslash continuations so each entry is one shell script.
    merged, pending = [], ''
    for line in lines:
        pending += line
        if pending.rstrip().endswith('\\'):
            pending = pending.rstrip()[:-1] + ' '
        else:
            merged.append(pending)
            pending = ''
    if pending:
        merged.append(pending)
    lines = merged
    staging = work / '.theos' / '_'
    (staging / 'DEBIAN').mkdir(parents=True)
    for scheme, expected in [(None, 'iphoneos-arm64'), ('rootless', 'iphoneos-arm64'),
                             ('roothide', 'iphoneos-arm64e')]:
        staged = staging / 'DEBIAN/control'
        staged.write_text('Package: local.notifybubbles\nName: x\nVersion: 9.9.9\n'
                          'Architecture: iphoneos-arm64e\nInstalled-Size: 1\n')
        (staging / 'DEBIAN/postinst').unlink(missing_ok=True)
        env = dict(os.environ, THEOS=str(theos), THEOS_STAGING_DIR=str(staging),
                   THEOS_LAYOUT_DIR=str(work / 'layout'),
                   **({} if scheme is None else {'THEOS_PACKAGE_SCHEME': scheme}))
        # Expand make variables in the recipe the way make would, then run it.
        # --eval is GNU-make 4.0+ only and Apple's /usr/bin/make is 3.81, so the
        # recipe is handed over through an injected makefile instead.
        (work / 'scheme-recipe.mk').write_text(
            'before-package::\n\t' + '\n\t'.join('@:' if not l.strip() else l for l in lines) + '\n')
        expanded = subprocess.run([make, '-s', '-C', str(work), '-f', 'Makefile',
                                   '-f', 'scheme-recipe.mk', '-n', 'before-package'],
                                  env=env, capture_output=True, text=True)
        assert expanded.returncode == 0, expanded.stdout + expanded.stderr
        script = '\n'.join(line for line in expanded.stdout.splitlines()
                           if line.strip() and line.strip() != ':')
        result = subprocess.run(['/bin/sh', '-c', script], cwd=str(work), env=env,
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        text = staged.read_text()
        assert 'Architecture: ' + expected in text, (scheme, text)
        assert re.search(r'^Version: 9\.9\.9$', text, re.M), text
        postinst = staging / 'DEBIAN/postinst'
        assert postinst.is_file() and postinst.stat().st_mode & 0o777 == 0o755, 'postinst mode'
        print('PASS: before-package staged ' + expected + (' (default)' if scheme is None else ' (' + scheme + ')'))

print('PASS: rootless default, roothide override (make variable and environment) and scheme-specific Architecture staging')
