"""Reproduce isolated installer regressions and read-only build/CI contracts.

Run from any directory. Each test gets private TEMP/TMP/APPDATA/LOCALAPPDATA.
No real Setup entry, installed product, startup-registry or logging test runs.
Use --output-dir and --isolation-root for a fresh reproduction. Existing result
files are never overwritten, and the isolation root must not already exist.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
RAW = HERE / "raw"
ISOLATION = ROOT / ".tmp/pr57-delivery-review-20260919/tests"
TESTS = [
    ("Test-PackageValidation", "ps5", "installer/simple/Test-PackageValidation.ps1"),
    ("Test-ProfileRemoval", "ps5", "installer/simple/Test-ProfileRemoval.ps1"),
    ("Test-Manage", "ps5", "installer/simple/Test-Manage.ps1"),
    ("Test-ProcessWait", "ps5", "installer/simple/Test-ProcessWait.ps1"),
    ("validate-build-contract", "ps7", "tools/validate-build-contract.ps1"),
    ("test_workflow_contract", None, "tools/ci/test_workflow_contract.py"),
]


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=RAW,
                        help="Directory for logs and results (default: original raw directory)")
    parser.add_argument("--isolation-root", type=Path, default=ISOLATION,
                        help="New directory for private test environments; must not exist")
    args = parser.parse_args()
    output_dir = args.output_dir.resolve()
    isolation_root = args.isolation_root.resolve()
    expected_files = [output_dir / "local-validation-summary.json"]
    expected_files += [output_dir / f"{name}.{suffix}"
                       for name, _, _ in TESTS
                       for suffix in ("stdout.log", "stderr.log", "result.json")]
    collisions = [path for path in expected_files if path.exists() or path.is_symlink()]
    if collisions:
        parser.error("Refusing to overwrite validation evidence; select a fresh "
                     f"--output-dir. Existing file: {collisions[0]}")
    if isolation_root.exists() or isolation_root.is_symlink():
        parser.error("--isolation-root must be a new directory: " + str(isolation_root))
    if output_dir.exists() and not output_dir.is_dir():
        parser.error("--output-dir is not a directory: " + str(output_dir))
    output_dir.mkdir(parents=True, exist_ok=True)
    isolation_root.mkdir(parents=True, exist_ok=False)
    source_head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()
    results = []
    for name, edition, source in TESTS:
        private_root = isolation_root / name
        environment = dict(os.environ)
        isolation = {}
        for key in ("TEMP", "TMP", "APPDATA", "LOCALAPPDATA"):
            path = private_root / key.lower()
            path.mkdir(parents=True, exist_ok=True)
            environment[key] = str(path)
            isolation[key] = str(path)
        environment["PYTHONUTF8"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        command = [sys.executable, "-X", "utf8"]
        if edition:
            command += ["tools/powershell/run_checked.py", "--script", source,
                        "--edition", edition]
        else:
            command += [source]
        started = utc_now()
        timer = time.monotonic()
        completed = subprocess.run(command, cwd=ROOT, env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout = output_dir / f"{name}.stdout.log"
        stderr = output_dir / f"{name}.stderr.log"
        with stdout.open("xb") as stream:
            stream.write(completed.stdout)
        with stderr.open("xb") as stream:
            stream.write(completed.stderr)
        result = {
            "name": name,
            "source_head": source_head,
            "script": source,
            "script_sha256": hashlib.sha256((ROOT / source).read_bytes()).hexdigest(),
            "edition": edition,
            "command": command,
            "working_directory": str(ROOT),
            "output_directory": str(output_dir),
            "environment_isolation": isolation,
            "started_at": started,
            "finished_at": utc_now(),
            "duration_seconds": round(time.monotonic() - timer, 3),
            "exit_code": completed.returncode,
            "stdout": stdout.name,
            "stdout_sha256": hashlib.sha256(completed.stdout).hexdigest(),
            "stderr": stderr.name,
            "stderr_sha256": hashlib.sha256(completed.stderr).hexdigest(),
        }
        with (output_dir / f"{name}.result.json").open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(result, indent=2) + "\n")
        results.append(result)
        print(f"{name}: exit {completed.returncode}", flush=True)
        if completed.returncode:
            break
    passed = len(results) == len(TESTS) and all(r["exit_code"] == 0 for r in results)
    summary = {"passed": passed, "results": results,
               "boundary": "Synthetic fixtures/processes and read-only source checks only; no real Setup, product processes, registration, default input method or user data operations."}
    with (output_dir / "local-validation-summary.json").open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(summary, indent=2) + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
