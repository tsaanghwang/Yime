#!/usr/bin/env python3
"""Validate the Windows toolchain lock and its repository integration."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LOCK = REPO_ROOT / "tools" / "toolchain.lock.json"
OFFLINE_RECOVERY_NOTE = "必要时可以制作一份可离线恢复的 Windows 构建环境包或 VM 镜像。"


class VerificationError(RuntimeError):
    """Raised when the toolchain lock is incomplete or conflicts with the build."""


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise VerificationError("toolchain lock root must be an object")
    return value


def verify(lock_path: Path = DEFAULT_LOCK) -> dict[str, Any]:
    lock = _load(lock_path.resolve())
    if lock.get("schema_version") != 1:
        raise VerificationError("unsupported toolchain lock schema")
    if lock.get("offline_recovery_note") != OFFLINE_RECOVERY_NOTE:
        raise VerificationError("toolchain lock has no approved offline recovery note")
    tools = lock.get("tools")
    if not isinstance(tools, list) or not tools:
        raise VerificationError("toolchain lock has no tools")
    seen: set[str] = set()
    artifact_count = 0
    for raw in tools:
        if not isinstance(raw, dict):
            raise VerificationError("toolchain record must be an object")
        tool_id = str(raw.get("id") or "")
        if not tool_id or tool_id in seen:
            raise VerificationError(f"invalid or duplicate toolchain ID: {tool_id!r}")
        seen.add(tool_id)
        if not str(raw.get("version") or "") or not str(raw.get("verify") or ""):
            raise VerificationError(f"toolchain {tool_id} lacks version or verifier")
        acquisition = raw.get("acquisition")
        if not isinstance(acquisition, dict):
            raise VerificationError(f"toolchain {tool_id} lacks acquisition data")
        url = str(acquisition.get("url") or "")
        if urlparse(url).scheme != "https":
            raise VerificationError(f"toolchain {tool_id} URL must use HTTPS")
        digest = str(acquisition.get("sha256") or "").lower()
        no_artifact_reason = str(acquisition.get("no_single_artifact_reason") or "")
        if digest:
            if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
                raise VerificationError(f"toolchain {tool_id} has invalid SHA-256")
            size = acquisition.get("size")
            if tool_id != "rust_i686_host" and (
                isinstance(size, bool) or not isinstance(size, int) or size <= 0
            ):
                raise VerificationError(f"toolchain {tool_id} has no artifact size")
            artifact_count += 1
        elif not no_artifact_reason:
            raise VerificationError(
                f"toolchain {tool_id} needs a SHA-256 or no-single-artifact reason"
            )

    required_ids = {
        "github_windows_runner",
        "visual_studio_build_tools",
        "windows_sdk",
        "cmake",
        "go",
        "python",
        "rust_i686_host",
        "nsis",
        "msys2_ucrt64_gcc",
        "go_winres",
    }
    if seen != required_ids:
        raise VerificationError(
            f"toolchain ID set mismatch: missing={sorted(required_ids - seen)}, "
            f"extra={sorted(seen - required_ids)}"
        )

    workflow = (REPO_ROOT / ".github" / "workflows" / "ci.yaml").read_text(
        encoding="utf-8"
    )
    build = (REPO_ROOT / "go-backend" / "build.bat").read_text(encoding="utf-8")
    cmake = (REPO_ROOT / "CMakeLists.txt").read_text(encoding="utf-8")
    for fragment in (
        "runs-on: windows-2022",
        "go-version: '1.26.4'",
        "python-version: '3.14'",
        "nsis-version: 3.08",
    ):
        if fragment not in workflow:
            raise VerificationError(f"CI no longer matches toolchain lock: {fragment}")
    if "third_party\\go-winres" not in build or "go build -mod=vendor" not in build:
        raise VerificationError("go-backend no longer builds vendored go-winres")
    if 'Rust_TOOLCHAIN "stable-i686-pc-windows-msvc"' not in cmake:
        raise VerificationError("CMake no longer pins the i686 Rust host toolchain")
    return {
        "decision": "pass",
        "lock_id": lock.get("lock_id"),
        "tool_count": len(tools),
        "hashed_artifact_count": artifact_count,
    }


def main() -> int:
    try:
        report = verify()
    except (OSError, ValueError, json.JSONDecodeError, VerificationError) as exc:
        print(f"FAIL toolchain lock: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
