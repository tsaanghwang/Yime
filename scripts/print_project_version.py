from __future__ import annotations

import tomllib
from pathlib import Path


def main() -> None:
    payload = tomllib.loads(Path("pyproject.toml").read_text(encoding="utf-8"))
    print(payload["project"]["version"])


if __name__ == "__main__":
    main()
