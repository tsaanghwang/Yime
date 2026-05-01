from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_ROOT.parent
YINJIE_CODE_PATH = PACKAGE_ROOT / "yinjie_code.json"
KEY_TO_CODE_PATH = PACKAGE_ROOT / "key_to_code.json"


__all__ = [
    "KEY_TO_CODE_PATH",
    "PACKAGE_ROOT",
    "REPO_ROOT",
    "YINJIE_CODE_PATH",
]
