"""Shared helpers for legacy syllable analysis scripts."""

import sys
from pathlib import Path
import os


REPO_ROOT = Path(__file__).resolve().parents[2]

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def flatten_grouped_ganyin(document: dict) -> dict[str, str]:
    grouped = document.get("ganyin", {})
    return {
        key: value
        for group in grouped.values()
        for key, value in group.items()
    }


def configure_temp_analyzer_output(analyzer, temp_dir: str) -> None:
    analyzer.output_dir = temp_dir
    analyzer.shouyin_path = os.path.join(temp_dir, "shouyin.json")
    analyzer.ganyin_path = os.path.join(temp_dir, "ganyin.json")
