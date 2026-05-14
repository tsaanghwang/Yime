from __future__ import annotations

import shutil
from datetime import datetime
from pathlib import Path


def prune_backup_files(backup_dir: Path, pattern: str, retain_count: int) -> list[Path]:
    if retain_count <= 0:
        return []

    backups = sorted(backup_dir.glob(pattern), key=lambda path: path.name, reverse=True)
    stale_backups = backups[retain_count:]
    removed: list[Path] = []
    for path in stale_backups:
        path.unlink(missing_ok=True)
        removed.append(path)
    return removed


def create_timestamped_backup(
    db_path: Path,
    *,
    backup_dir: Path,
    backup_tag: str,
    retain_count: int,
) -> tuple[Path, list[Path]]:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = backup_dir / f"{db_path.stem}.{backup_tag}_{timestamp}.bak"
    shutil.copy2(db_path, backup_path)
    removed = prune_backup_files(
        backup_dir,
        f"{db_path.stem}.{backup_tag}_*.bak",
        retain_count,
    )
    return backup_path, removed
