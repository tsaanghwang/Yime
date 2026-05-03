from __future__ import annotations

import subprocess
import sys
from pathlib import Path


PUBLIC_MODULES = [
    "yime.database",
    "yime.db_manager",
    "yime.pinyin_converter",
    "yime.pinyin_importer",
    "yime.syllable_decoder",
    "yime.utils_charfilter",
    "yime.canonical_yime_mapping",
    "yime.export_runtime_candidates_json",
    "yime.import_danzi_into_prototype_tables",
    "yime.import_duozi_into_prototype_tables",
    "yime.refresh_runtime_yime_codes",
    "yime.input_method",
]


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    output_dir = project_root / "docs"

    command = [
        sys.executable,
        "-m",
        "pdoc",
        "--html",
        "--force",
        "--skip-errors",
        "--output-dir",
        str(output_dir),
        *PUBLIC_MODULES,
    ]
    return subprocess.run(command, cwd=project_root, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
