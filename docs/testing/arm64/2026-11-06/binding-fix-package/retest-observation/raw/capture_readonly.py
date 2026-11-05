"""Capture read-only installed state, lock users and boot evidence via checked PS7."""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path('C:/dev/Yime/.wt/bindfix')
OUT = ROOT / '.generated/binding-retest-20261106'
PRIOR = ROOT / '.generated/binding-upgrade-20261106'
env = os.environ.copy()
env['PATH'] = 'C:/dev/Yime/.wt/armfull/.generated/arm64-maintenance-shell/powershell;' + env['PATH']
provenance = []
for script, label in [(OUT / 'observe-boot.ps1', 'boot-observation'), (PRIOR / 'query-asus-18u-locks.ps1', 'current-dll-users'), (PRIOR / 'capture-installed.ps1', 'current-state')]:
    params = OUT / (label + '-params.json')
    report = OUT / (label + '.json')
    log = OUT / (label + '.log')
    assert not report.exists() and not params.exists() and not log.exists(), 'Do not overwrite evidence'
    params.write_text(json.dumps({'Report': str(report)}), encoding='utf-8')
    command = [sys.executable, '-B', '-X', 'utf8', str(ROOT / 'tools/powershell/run_checked.py'), '--edition', 'ps7', '--script', str(script), '--params-file', str(params)]
    provenance.append({'script': str(script), 'sha256': hashlib.sha256(script.read_bytes()).hexdigest(), 'command': command})
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
    log.write_bytes(result.stdout + result.stderr)
    print(result.stdout.decode('utf-8', errors='replace'), flush=True)
    if result.returncode:
        print(result.stderr.decode('utf-8', errors='replace'), flush=True)
        raise SystemExit(result.returncode)
(OUT / 'snapshot-tool-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')
