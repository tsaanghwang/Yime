import hashlib
import json
from pathlib import Path
import shutil

repo = Path.cwd()
delivery = Path('C:/dev/Yime-deliveries/registration-fix-20260929')
report = repo / 'docs/testing/simple-maintenance/2026-09-29/registration-fix'
raw = report / 'raw/local'
raw.mkdir(parents=True, exist_ok=True)
query = repo / '.tmp/registration-query-390db0972c7e42e09505b589966eb9b7'
shutil.copy2(query/'transcript.txt',raw/'registration-query-transcript.txt')
for arch in ('x64','x86'):
    shutil.copy2(query/arch/'Testing/Temporary/LastTest.log',raw/f'registration-query-{arch}.log')
for name in ('build-contract','workflow-contract','package-validation','profile-removal','manage','process-wait'):
    for suffix in ('.log','.command.json'):
        shutil.copy2(delivery/(name+suffix),raw/(name+suffix))
index=[]
for p in sorted(raw.iterdir()):
    index.append(dict(path=p.relative_to(report).as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
(report/'local-validation.json').write_text(json.dumps(dict(
    scope='Source regression validation before commit; no installed product changes',
    registration_command=['python','tools/powershell/run_checked.py','--script','tools/yimecore/test-registration-query.ps1','--edition','ps7'],
    architectures=['x64','x86'], passed=True, installed_acceptance=False,
    duplicate_guard='Unchanged production guard reviewed; September 28 controlled diagnostic is historical evidence, not rerun',
    files=index),indent=2)+'\n',encoding='utf-8')
print('Recorded local validation evidence')
