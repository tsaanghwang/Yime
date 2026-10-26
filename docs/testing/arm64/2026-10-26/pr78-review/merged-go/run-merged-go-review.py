from pathlib import Path
import datetime
import hashlib
import json
import os
import subprocess
import uuid

repo = Path(__file__).resolve().parent.parent
root = repo / '.tmp' / ('pr78-merged-go-' + uuid.uuid4().hex[:8])
root.mkdir()
env = {k: v for k, v in os.environ.items() if not k.upper().startswith('YIME_')}
env.update(GOOS='windows', GOARCH='arm64', CGO_ENABLED='0', GOFLAGS='', GOWORK='off', GOENV='off', GOTOOLCHAIN='local')
for name in ('TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA', 'GOCACHE', 'GOTMPDIR'):
    folder = root / name.lower()
    folder.mkdir()
    env[name] = str(folder)
go = r'C:\dev\Yime\.generated\arm64-toolchain\go1.25.14\go\bin\go.exe'
git = r'C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd\git.exe'
command = [go, 'test', '-count=1', '-json', './cmd/yime-touch-keyboard']
print('Evidence: ' + str(root), flush=True)
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
with (root / 'go-test.jsonl').open('xb') as out, (root / 'go-test.stderr.txt').open('xb') as err:
    process = subprocess.run(command, cwd=repo / 'go-backend', env=env, stdout=out, stderr=err)
events = [json.loads(line) for line in (root / 'go-test.jsonl').read_text(encoding='utf-8').splitlines() if line]
summary = {'started_utc': started, 'finished_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'source_commit': subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
           'command': command, 'exit_code': process.returncode,
           'test_pass_events': sum(e.get('Action') == 'pass' and 'Test' in e for e in events),
           'test_skip_events': sum(e.get('Action') == 'skip' and 'Test' in e for e in events),
           'failed_tests': [e['Test'] for e in events if e.get('Action') == 'fail' and 'Test' in e],
           'go_test_sha256': hashlib.sha256((root / 'go-test.jsonl').read_bytes()).hexdigest(),
           'scope': 'Native ARM64 source regressions after merging main; disposable own-window fixtures, no real application or physical-input acceptance'}
(root / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False), flush=True)
raise SystemExit(process.returncode)
