from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXTERNAL_REPO = ROOT.parent / "Yime-keyboard-layout"
EXTERNAL_REPO = Path(
    os.environ.get("YIME_KEYBOARD_LAYOUT_REPO", str(DEFAULT_EXTERNAL_REPO))
).expanduser().resolve()
TARGET_SCRIPT = EXTERNAL_REPO / "tools" / "run_msklc_install_pipeline.py"


def main() -> None:
    if not TARGET_SCRIPT.exists():
        raise SystemExit(
            "The MSKLC install chain has been moved out of the main repo. "
            "Set YIME_KEYBOARD_LAYOUT_REPO or place the external repo next to the main repo. "
            f"Expected helper script at: {TARGET_SCRIPT}"
        )

    command = [sys.executable, str(TARGET_SCRIPT), *sys.argv[1:]]
    raise SystemExit(subprocess.call(command, cwd=EXTERNAL_REPO))


if __name__ == "__main__":
    main()
