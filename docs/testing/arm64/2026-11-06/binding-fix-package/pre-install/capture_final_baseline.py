"""Read-only final snapshot through the repository PowerShell entry."""
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path('C:/dev/Yime/.wt/bindfix')
OUT = ROOT / '.generated/binding-upgrade-20261106'
ORIGINAL = Path('C:/dev/Yime/.wt/armfull/.generated/armfull-tools')
env = os.environ.copy()
env['PATH'] = 'C:/Users/tsaan/AppData/Local/Microsoft/WindowsApps/Microsoft.PowerShell_8wekyb3d8bbwe;' + env['PATH']
provenance = []
for script_name, label in [('capture-installed.ps1', 'prepared-state'), ('query-asus-18u-locks.ps1', 'prepared-dll-users')]:
    script = OUT / script_name
    assert not script.exists(), 'Preserve previous snapshot scripts.'
    shutil.copy2(ORIGINAL / script_name, script)
    provenance.append({'source': str(ORIGINAL / script_name), 'copiedTo': str(script), 'sha256': hashlib.sha256(script.read_bytes()).hexdigest()})
    params = OUT / (label + '-params.json')
    report = OUT / (label + '.json')
    assert not params.exists() and not report.exists()
    params.write_text(json.dumps({'Report': str(report)}), encoding='utf-8')
    command = [sys.executable, '-X', 'utf8', str(ROOT / 'tools/powershell/run_checked.py'), '--edition', 'ps7', '--script', str(script), '--params-file', str(params)]
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
    (OUT / (label + '.log')).write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, label + ' failed'
    record = json.loads(report.read_text(encoding='utf-8-sig'))
    if label == 'prepared-state':
        summary = [{'id': p['id'], 'version': p['version'], 'payloadCount': len(p['payload']), 'processes': p['processes']} for p in record['products']]
        print(json.dumps({'products': summary, 'defaultInputOverride': record['defaultInputOverride']}, ensure_ascii=False))
    else:
        print(json.dumps(record, ensure_ascii=False))
(OUT / 'snapshot-tool-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')
