"""Run only in a disposable native Windows ARM64 VM. Never run on ASUS.

The first unexpected result stops the script and leaves every output directory intact.
This is a real native negative test; test_source_contract.py is the offline check.
"""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


WAIT_OBJECT_0 = 0
SYNCHRONIZE = 0x00100000
ERROR_INVALID_PARAMETER = 87


def snapshot(directory: Path):
    result = {}
    for path in [directory, *sorted(directory.rglob("*"))]:
        stat = path.stat()
        result[str(path.relative_to(directory))] = (
            path.is_dir(), stat.st_size, stat.st_mtime_ns,
            hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None,
        )
    return result


def run(probe: Path, pwsh: Path, output: Path, case: str):
    return subprocess.run(
        [str(probe), "--pwsh", str(pwsh), "--output", str(output), "--case", case],
        cwd=str(probe.parent), capture_output=True, timeout=90, check=False,
    )


def assert_stopped(pid: int):
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.argtypes = (ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32)
    kernel32.OpenProcess.restype = ctypes.c_void_p
    kernel32.WaitForSingleObject.argtypes = (ctypes.c_void_p, ctypes.c_uint32)
    kernel32.WaitForSingleObject.restype = ctypes.c_uint32
    kernel32.CloseHandle.argtypes = (ctypes.c_void_p,)
    handle = kernel32.OpenProcess(SYNCHRONIZE, False, pid)
    if not handle:
        error = ctypes.get_last_error()
        if error == ERROR_INVALID_PARAMETER:
            return
        raise AssertionError(f"cannot confirm pid {pid} stopped: Win32={error}")
    try:
        assert kernel32.WaitForSingleObject(handle, 0) == WAIT_OBJECT_0, f"pid {pid} still running"
    finally:
        kernel32.CloseHandle(handle)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", required=True, type=Path)
    parser.add_argument("--pwsh", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path,
                        help="new output root on local NTFS; never reused")
    args = parser.parse_args()
    probe, pwsh, root = (p.resolve(strict=True) for p in (args.probe, args.pwsh, args.root.parent))
    root = root / args.root.name
    assert not root.exists(), "root must be absent; refusing to reuse evidence"
    root.mkdir()

    existing = root / "probe-existing"
    existing.mkdir()
    (existing / "failure.txt").write_bytes(b"preexisting failure sentinel\n")
    (existing / "keep.bin").write_bytes(b"unchanged\x00\xff")
    before = snapshot(existing)
    result = run(probe, pwsh, existing, "share")
    (root / "existing.stdout.bin").write_bytes(result.stdout)
    (root / "existing.stderr.bin").write_bytes(result.stderr)
    (root / "existing.exit.txt").write_text(f"{result.returncode}\n", encoding="ascii")
    assert result.returncode != 0, "existing directory was accepted"
    assert snapshot(existing) == before, "rejected existing directory changed"

    for case, event in (("timeout-child", "timeout-child-process"),
                        ("timeout-actor", "actor-process")):
        output = root / f"probe-{case}"
        result = run(probe, pwsh, output, case)
        (root / f"{case}.stdout.bin").write_bytes(result.stdout)
        (root / f"{case}.stderr.bin").write_bytes(result.stderr)
        (root / f"{case}.exit.txt").write_text(f"{result.returncode}\n", encoding="ascii")
        assert result.returncode != 0, f"{case} unexpectedly passed"
        rows = [json.loads(line) for line in (output / "events.jsonl").read_text(encoding="utf-8").splitlines()]
        assert not any(row.get("event") == "case-passed" for row in rows), f"{case} claimed success"
        failure = next(row for row in rows if row.get("event") == "case-failed")
        assert "terminated and reaped" in failure["reason"], f"{case} stop not confirmed"
        pid = next(row["pid"] for row in rows if row.get("event") == event)
        assert_stopped(pid)
    print("VM negative tests: existing directory unchanged; child and actor timed out and reaped")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"STOP: {exc}", file=sys.stderr)
        raise SystemExit(1)
