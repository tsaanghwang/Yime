#!/usr/bin/env python3
"""Verify a Yime-local replay of the approved fixed core handoff."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


MODULE_DIR = Path(__file__).resolve().parent
if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

from verify_target_lock import DEFAULT_LOCK, REPO_ROOT, VerificationError, verify


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VerificationError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise VerificationError(f"JSON root must be an object: {path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise VerificationError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _expect(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise VerificationError(
            f"{label} mismatch: expected {expected!r}, got {actual!r}"
        )


def verify_replay(
    output_dir: Path,
    *,
    lock_path: Path = DEFAULT_LOCK,
    repo_root: Path = REPO_ROOT,
) -> dict[str, Any]:
    locked = verify(lock_path, repo_root)
    target = locked["target"]
    artifacts = {
        str(item["role"]): item for item in locked["verified_artifacts"]
    }

    replay_manifest = _read_json(output_dir / "yime_lexicon_manifest.json")
    replay_source = _read_json(output_dir / "yime_core_source_manifest.json")
    _expect(
        replay_manifest.get("entry_count"),
        target.get("entry_count"),
        "replay manifest entry_count",
    )
    _expect(
        replay_manifest.get("source_sha256"),
        target.get("source_dictionary_sha256"),
        "replay manifest source SHA-256",
    )
    _expect(replay_source.get("source_project"), "Yime", "replay source project")
    _expect(
        replay_source.get("approved_target_lock"),
        lock_path.name,
        "replay approved target lock",
    )
    _expect(
        replay_source.get("source_dictionary_sha256"),
        target.get("source_dictionary_sha256"),
        "replay source dictionary SHA-256",
    )
    _expect(
        replay_source.get("source_selection_sha256"),
        target.get("source_selection_sha256"),
        "replay source selection SHA-256",
    )
    _expect(
        replay_source.get("entry_count"),
        target.get("entry_count"),
        "replay source entry_count",
    )
    _expect(
        replay_source.get("distinct_texts"),
        target.get("distinct_texts"),
        "replay source distinct_texts",
    )
    if not str(replay_source.get("source_revision", "")).strip():
        raise VerificationError("replay source revision is empty")

    output_roles = (
        ("full_mode_dictionary", "yime_full.dict.yaml"),
        ("variable_mode_dictionary", "yime_variable.dict.yaml"),
        ("shorthand_mode_dictionary", "yime_shorthand.dict.yaml"),
    )
    output_hashes = replay_manifest.get("output_sha256")
    if not isinstance(output_hashes, dict):
        raise VerificationError("replay manifest lacks output_sha256")
    verified_outputs: dict[str, str] = {}
    for role, name in output_roles:
        digest = _sha256(output_dir / name)
        expected = str(artifacts[role]["sha256"])
        _expect(digest, expected, f"replay {name} SHA-256")
        _expect(output_hashes.get(name), expected, f"replay manifest {name} SHA-256")
        verified_outputs[name] = digest

    reverse_digest = _sha256(output_dir / "yime_pinyin_reverse_source.tsv")
    _expect(
        reverse_digest,
        artifacts["reverse_pinyin_source"]["sha256"],
        "replay reverse-Pinyin source SHA-256",
    )

    return {
        "decision": "pass",
        "lock_id": locked["lock_id"],
        "entry_count": target["entry_count"],
        "distinct_texts": target["distinct_texts"],
        "source_dictionary_sha256": target["source_dictionary_sha256"],
        "source_selection_sha256": target["source_selection_sha256"],
        "output_sha256": verified_outputs,
        "reverse_pinyin_source_sha256": reverse_digest,
        "source_revision": replay_source["source_revision"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    args = parser.parse_args()
    try:
        report = verify_replay(
            args.output_dir.resolve(),
            lock_path=args.lock.resolve(),
            repo_root=args.repo_root.resolve(),
        )
    except VerificationError as exc:
        print(f"FAIL replayed handoff: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
