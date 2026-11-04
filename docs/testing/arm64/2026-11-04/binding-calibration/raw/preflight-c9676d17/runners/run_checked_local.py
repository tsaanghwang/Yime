import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
env = os.environ.copy()
env['PATH'] = r'C:\Users\tsaan\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe;' + env.get('PATH', '')
temp = root / '.generated' / 'armfull-tools' / 'ps-temp'
temp.mkdir(parents=True, exist_ok=True)
env['TEMP'] = env['TMP'] = str(temp)
raise SystemExit(subprocess.run([sys.executable, str(root / 'tools/powershell/run_checked.py'), *sys.argv[1:]], cwd=root, env=env).returncode)
