"""兼容入口：转发到 utils.pinyin_normalizer 的唯一 CLI 入口。"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from utils.pinyin_normalizer import main

if __name__ == "__main__":
    raise SystemExit(main())
