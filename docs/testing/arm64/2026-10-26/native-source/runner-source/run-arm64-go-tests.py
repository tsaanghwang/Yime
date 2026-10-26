from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(repo / 'tools'))
from yimecore.collect_arm64_host import get_machine_architecture, read_pe_machine
host = get_machine_architecture()
assert host['native_architecture'] == 'arm64'
go = repo / '.generated/arm64-toolchain/go1.25.14/go/bin/go.exe'
assert read_pe_machine(go)['machine'] == '0xaa64'
evidence = repo / 'docs/testing/arm64/2026-10-26/native-go'
evidence.mkdir()
state = repo / '.tmp/arm64-go-native-20261026'
state.mkdir()
names = ['GOOS', 'GOARCH', 'CGO_ENABLED', 'GOTOOLCHAIN', 'GOFLAGS', 'GOWORK', 'GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'APPDATA', 'LOCALAPPDATA']
env = {k: v for k, v in os.environ.items() if k.upper() not in names and not k.upper().startswith('YIME_')}
env.update(GOOS='windows', GOARCH='arm64', CGO_ENABLED='0', GOTOOLCHAIN='local', GOFLAGS='', GOWORK='off')
for key in ['GOCACHE', 'GOMODCACHE', 'GOTMPDIR', 'TEMP', 'TMP', 'APPDATA', 'LOCALAPPDATA']:
    path = state / key.lower()
    path.mkdir()
    env[key] = str(path)
packages = ['./input_methods/yime/yimecore', './input_methods/yime/yimebroker', './cmd/yimebroker',
            './cmd/yimecore-trial-runtime', './input_methods/yime/codemode', './input_methods/yime/runtimeidentity']
started = datetime.now(timezone.utc).isoformat()
log = evidence / 'go-test.jsonl'
with log.open('xb') as output:
    result = subprocess.run([str(go), 'test', '-json', '-count=1', *packages], cwd=repo/'go-backend', env=env, stdout=output, stderr=subprocess.STDOUT, timeout=1200)
events = []
for line in log.read_text(encoding='utf-8', errors='replace').splitlines():
    try:
        events.append(json.loads(line))
    except json.JSONDecodeError:
        pass
checks = [e for e in events if e.get('Action') in ['pass', 'fail', 'skip']]
summary = {'scope': 'YimeCore ARM64 isolated source Go tests; no installed or physical input acceptance',
           'started_at_utc': started, 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
           'host': host, 'go_version': subprocess.check_output([str(go), 'version'], text=True).strip(),
           'packages': packages, 'exit_code': result.returncode,
           'package_results': [e for e in checks if not e.get('Test')],
           'test_events': {action: sum(e['Action']==action and bool(e.get('Test')) for e in checks) for action in ['pass', 'fail', 'skip']},
           'isolated_state_root': str(state), 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
           'installation_performed': False, 'physical_acceptance': False}
with (evidence/'summary.json').open('x', encoding='utf-8') as output:
    json.dump(summary, output, ensure_ascii=False, indent=2)
print(json.dumps(summary, ensure_ascii=False, indent=2))
raise SystemExit(result.returncode)
