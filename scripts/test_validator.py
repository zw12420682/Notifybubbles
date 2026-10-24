from pathlib import Path
import shutil, subprocess, sys, tempfile

source=Path(__file__).resolve().parents[1]
# Fixtures must never be created inside the project (validate.py walks the tree,
# the copies would recurse into themselves). Use a real temporary directory.
base=Path(tempfile.mkdtemp(prefix='nfb-validator-cases-'))
cases=['clean','overlay','without_archive','unknown','older_keyboard_badges','missing_source','retired_built','missing_header','duplicate',
       'missing_test','missing_workflow_step','old_simulator','old_foundation']
for case in cases:
    with tempfile.TemporaryDirectory(prefix=case+'-',dir=base) as directory:
        project=Path(directory).resolve()
        assert project.is_relative_to(base)
        ignore=shutil.ignore_patterns('__pycache__','.git','.theos*','packages',*(['Legacy'] if case=='without_archive' else []))
        shutil.copytree(source,project,dirs_exist_ok=True,ignore=ignore)
        if case in ['overlay','retired_built']:
            for name in ['NFBAppBack.m','NFBBackRequest.m']:
                (project/'Sources'/name).write_text('#import \"MissingArchivedHeader.h\"\n',encoding='utf-8')
        if case=='unknown': (project/'Sources/Unexpected.m').write_text('// fixture\n',encoding='utf-8')
        if case=='older_keyboard_badges':
            for name in ['NFBDarkKeyboard.m','NFBTrollBadges.m']:
                (project/'Sources'/name).write_text('#import "UnusedMissingHeader.h"\n',encoding='utf-8')
        if case=='missing_source': (project/'Sources/NFBStateLedger.m').unlink()
        if case=='missing_header': (project/'Sources/NFBStateLedger.h').unlink()
        if case=='missing_test': (project/'Tests/StateLedgerTests.m').unlink()
        if case=='missing_workflow_step':
            p=project/'.github/workflows/build.yml'
            p.write_text(p.read_text(encoding='utf-8').replace('Tests/StateLedgerTests.m','Tests/UnrelatedTests.m'),encoding='utf-8',newline='\n')
        if case=='old_simulator':
            p=project/'scripts/test_desktop_simulator.py'
            p.write_text(p.read_text(encoding='utf-8').replace('NFBInterfaces.m','OldInterfaces.m'),encoding='utf-8',newline='\n')
        if case=='old_foundation':
            p=project/'.github/workflows/build.yml'
            p.write_text(p.read_text(encoding='utf-8').replace('Sources/NFBInterfaces.m','Sources/OldInterfaces.m'),encoding='utf-8',newline='\n')
        if case in ['retired_built','duplicate']:
            p=project/'Makefile'
            extra='Sources/NFBAppBack.m' if case=='retired_built' else 'Sources/Tweak.m'
            p.write_text(p.read_text(encoding='utf-8').replace('NotifyBubbles_FILES = ','NotifyBubbles_FILES = '+extra+' '),encoding='utf-8',newline='\n')
        run=subprocess.run([sys.executable,'-X','utf8',str(project/'scripts/validate.py')],capture_output=True,text=True,encoding='utf-8')
        expected=case in ['clean','overlay','without_archive','unknown','older_keyboard_badges']
        assert (run.returncode==0)==expected,(case,run.stdout,run.stderr)
        messages={'missing_source':'Missing build sources','retired_built':'Retired helpers must not be compiled','missing_header':'Missing active dependency','duplicate':'Duplicate implementation'}
        messages.update({'missing_test':'Missing test file: Tests/StateLedgerTests.m',
                         'missing_workflow_step':'Missing workflow test step for: StateLedgerTests.m',
                         'old_simulator':'Old simulator build command omits: NFBInterfaces.m',
                         'old_foundation':'Old Foundation test build command omits Sources/NFBInterfaces.m'})
        if case in messages: assert messages[case] in run.stderr,(case,run.stderr)
        if case in ['overlay','unknown','older_keyboard_badges']: assert 'NOTE: source files excluded from Makefile build inputs:' in run.stdout
        print('PASS:',case)
