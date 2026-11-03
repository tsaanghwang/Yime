"""Select the already verified protected PS7 while preserving the exact clean PATH."""
from pathlib import Path
import sys
repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / 'tools/powershell'))
import run_checked
shell = Path('C:/Program Files/Yime Maintenance/rime-pime/cb5bdf84f792130086fc86de41248c739dc94acfa089331183ee3137ab3c2dbd/maintenance/powershell/pwsh.exe')
if not shell.is_file():
    raise ValueError('expected existing protected shell')
original = run_checked.shutil.which
run_checked.shutil.which = lambda name: str(shell) if name == 'pwsh' else original(name)
raise SystemExit(run_checked.main())
