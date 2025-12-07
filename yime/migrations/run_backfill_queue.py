from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).parent
SCRIPT = ROOT / "backfill_mappings.py"

if not SCRIPT.exists():
    print("backfill_mappings.py not found at", SCRIPT)
    sys.exit(1)

# Default to --mode queue; forward any additional args (e.g. --apply --limit 100)
forward_args = ["--mode", "queue"] + sys.argv[1:]

cmd = [sys.executable, str(SCRIPT)] + forward_args
print("Running:", " ".join(cmd))
res = subprocess.run(cmd)
sys.exit(res.returncode)
