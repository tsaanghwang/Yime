import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path('C:/dev/Yime-deliveries/registration-fix-20260929')
root.mkdir(parents=True, exist_ok=True)
name, *command = sys.argv[1:]
log = root / (name + '.log')
record = root / (name + '.command.json')
if log.exists() or record.exists():
    raise SystemExit('Preserve earlier step evidence: ' + name)
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
with log.open('wb') as stream:
    result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                            env=dict(os.environ, PYTHONUTF8='1'))
record.write_text(json.dumps(dict(command=command, cwd=str(Path.cwd()), started_at=started,
    finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), exit_code=result.returncode), indent=2), encoding='utf-8')
print(json.dumps(dict(log=str(log), exit_code=result.returncode)))
print(log.read_text(encoding='utf-8-sig', errors='replace')[-4500:])
sys.exit(result.returncode)
