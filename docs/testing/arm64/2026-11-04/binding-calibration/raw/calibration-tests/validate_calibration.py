from pathlib import Path
import json, os, subprocess, sys

root = Path(__file__).resolve().parents[2]
out = root / '.generated/18u-calibration-validation'
out.mkdir(exist_ok=True)
env = os.environ.copy()
for variable, child in [('GOCACHE', 'cache'), ('GOTMPDIR', 'tmp'), ('GOPATH', 'path'), ('TEMP', 'tmp'), ('TMP', 'tmp')]:
    directory = root / '.generated/touch-full-tools' / child
    directory.mkdir(exist_ok=True)
    env[variable] = str(directory)
env.update(GOENV='off', GOTOOLCHAIN='local')
go = r'C:\dev\Yime\.generated\arm64-toolchain\go1.25.14\go\bin\go.exe'
commands = {
    'calibration-and-entry-contracts': ['test', '-json', '-count=1', './cmd/yime-touch-keyboard', '-run', 'TestCalibration|TestTouchSettingsFitTheScreenViewAtDifferentScales|TestTouchHeaderCalibrationRejectionKeepsPreviousGeometry|TestProfilesRejectTyposAndUnreviewed17U|TestPortable|TestInstalled'],
    'touchkeyboard-complete': ['test', '-json', '-count=1', './internal/touchkeyboard'],
    'vet': ['vet', './cmd/yime-touch-keyboard', './internal/touchkeyboard'],
}
summary = {'product': 'yimecore-18u', 'physicalAcceptance': False, 'installedPayloadChanged': False, 'productGUIStarted': False, 'commands': {}}
for name, args in commands.items():
    run = subprocess.run([go, *args], cwd=root/'go-backend', env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out/(name+'.log')).write_bytes(run.stdout)
    passes, skips, failures = [], [], []
    for line in run.stdout.decode('utf-8', errors='replace').splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not event.get('Test'):
            continue
        bucket = {'pass': passes, 'skip': skips, 'fail': failures}.get(event.get('Action'))
        if bucket is not None:
            bucket.append(event['Test'])
    summary['commands'][name] = {'arguments': args, 'exitCode': run.returncode, 'passedTopLevel': len([x for x in passes if '/' not in x]), 'passedSubtests': len([x for x in passes if '/' in x]), 'skipped': skips, 'failed': failures}
    print(name, summary['commands'][name], flush=True)
    if run.returncode or failures or skips:
        (out/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        sys.exit(1)
(out/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
