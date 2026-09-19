"""Capture the deliberately non-installing validation subset for this handoff audit.

This script runs from the repository root. It only changes isolated synthetic
test fixtures and evidence files; no real product Setup entry is executed.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[7]
OUT = Path(__file__).resolve().parent
PYTHON = sys.executable


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def python(*args: str) -> list[str]:
    return [PYTHON, "-X", "utf8", *args]


def ps(script: str, edition: str) -> list[str]:
    return python("tools/powershell/run_checked.py", "--script", script, "--edition", edition)


CHECKS = [
    ("package-validation-ps5", ps("installer/simple/Test-PackageValidation.ps1", "ps5")),
    ("profile-removal-mocks-ps5", ps("installer/simple/Test-ProfileRemoval.ps1", "ps5")),
    ("manage-synthetic-packages-ps5", ps("installer/simple/Test-Manage.ps1", "ps5")),
    ("legacy-retirement-mocks-ps5", ps("tools/yimecore/test-retire-legacy-entry.ps1", "ps5")),
    ("build-contract-ps7", ps("tools/validate-build-contract.ps1", "ps7")),
    ("powershell-wrapper-tests", python("-m", "unittest", "discover", "-s", "tools/powershell", "-p", "test_run_checked.py", "-v")),
    ("workflow-contract", python("tools/ci/test_workflow_contract.py")),
    ("shard-coverage-tests", python("-m", "unittest", "discover", "-s", "tools/ci", "-p", "test_shard_coverage.py", "-v")),
    ("repository-data-boundary", python("tools/lexicon/check_repository_data_boundary.py")),
    ("toolchain-lock", python("tools/verify_toolchain_lock.py")),
    ("external-archive-lock-metadata", python("tools/lexicon/verify_external_archive_lock.py")),
    ("vendored-dependencies", python("tools/verify_vendored_build_dependencies.py")),
    ("psc-outline-snapshot", python("tools/verify_psc_outline_snapshot.py")),
]


def run_check(item: tuple[str, list[str]]) -> dict:
    name, command = item
    started = datetime.now(timezone.utc).isoformat()
    begin = time.monotonic()
    environment = os.environ.copy()
    environment["PYTHONUTF8"] = "1"
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, timeout=600)
    stdout = OUT / f"{name}.stdout.txt"
    stderr = OUT / f"{name}.stderr.txt"
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    record = {
        "name": name,
        "command": command,
        "cwd": str(ROOT),
        "started_utc": started,
        "finished_utc": datetime.now(timezone.utc).isoformat(),
        "elapsed_seconds": round(time.monotonic() - begin, 3),
        "exit_code": result.returncode,
        "stdout": {"path": stdout.name, "bytes": len(result.stdout), "sha256": digest(stdout)},
        "stderr": {"path": stderr.name, "bytes": len(result.stderr), "sha256": digest(stderr)},
    }
    (OUT / f"{name}.command.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{name}: exit {result.returncode}", flush=True)
    return record


def main() -> int:
    if not (ROOT / "AGENTS.md").is_file():
        raise RuntimeError(f"Incorrect repository root: {ROOT}")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    source_paths = sorted(set(
        ["AGENTS.md", "installer/simple/Product.psm1", "installer/simple/Setup.ps1", "installer/simple/Manage-Products.ps1",
         "tools/powershell/run_checked.py", "tools/powershell/test_run_checked.py", "tools/ci/test_shard_coverage.py",
         "tools/ci/verify_shard_coverage.py", ".github/workflows/ci.yaml", "tools/yimecore/retire-legacy-entry.ps1",
         "tools/yimecore/development-scope.ps1"]
        + [part for _, command in CHECKS for part in command if part.endswith((".py", ".ps1")) and (ROOT / part).is_file()]
    ))
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(run_check, CHECKS))
    summary = {
        "schema": "yime-current-readiness-release-local-checks-v1",
        "commit": commit,
        "branch": branch,
        "source_files": [{"path": path, "sha256": digest(ROOT / path)} for path in source_paths],
        "checks": results,
        "passed": all(row["exit_code"] == 0 for row in results),
        "boundaries": {
            "real_package_validated": False,
            "historical_package_rebuilt": False,
            "installed_acceptance": False,
            "real_setup_install_uninstall_executed": False,
            "product_processes_started_stopped_or_restarted": False,
            "registry_default_input_method_or_user_data_changed": False,
            "allowed_test_writes": "Synthetic temporary fixtures and this evidence directory only.",
            "manage_test": "Only generated temp Setup.ps1 log fixtures run in child PowerShell processes.",
            "wrapper_test_editions": "The wrapper's own compatibility contract tests ps5 and ps7; installer tests use ps5, build contract uses ps7.",
        },
        "not_run": [
            {"test": "Test-Product.ps1", "reason": "No actual historical packages available; cannot substitute synthetic packages for this test."},
            {"test": "Test-Startup.ps1", "reason": "Writes isolated real registry test keys; excluded from this strictly non-system-mutating local run."},
            {"test": "Test-Logging.ps1", "reason": "Uses real setup logging under the user profile; excluded."},
            {"test": "Test-ProcessWait.ps1", "reason": "Creates a standalone surviving child process; excluded."},
            {"test": "Native registered/live host acceptance", "reason": "Not authorized for this source/package audit."},
        ],
    }
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
