#!/usr/bin/env python3
"""Run six mandatory Windows x64 entry-point checks; never request registration.

Only absent or deliberately invalid DPAPI files are supplied to recovery. On a
non-MyComputer CI host that mode is rejected earlier by the hostname gate; this
is recorded, NOT counted as exercising DPAPI or successful recovery.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

FIELDS = {
    "schema", "scope", "mode", "status", "stage", "code", "writesStarted",
    "cleanupVerified", "preconditions", "prerequisitesSatisfied", "actualHostName",
    "threadLanguage", "currentLanguage", "dllSha256", "dllPresent", "publisherTrust",
    "brokerEditingVerified", "profileActivationApiVerified", "actualDllActivationVerified",
}
CONDITIONS = {
    "nativeX64", "hostMatches", "hkl0804", "tsf0804", "elevated",
    "identityAbsent", "dllVerified", "directTestAbsent",
}
BAD_LEDGER = b"deliberately-invalid-stage1-dpapi-format\n"


class GateFailure(Exception):
    pass


def need(value: bool, reason: str) -> None:
    if not value:
        raise GateFailure(reason)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, "duplicate-json-field")
        result[key] = value
    return result


def require_windows_x64() -> None:
    need(os.name == "nt", "windows-required-no-skip")
    need(ctypes.sizeof(ctypes.c_void_p) == 8, "native-amd64-python-required")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.IsWow64Process2.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ushort), ctypes.POINTER(ctypes.c_ushort)]
    kernel.IsWow64Process2.restype = ctypes.c_int
    process, native = ctypes.c_ushort(), ctypes.c_ushort()
    need(bool(kernel.IsWow64Process2(kernel.GetCurrentProcess(), ctypes.byref(process), ctypes.byref(native))), "native-architecture-query")
    need(process.value == 0 and native.value == 0x8664, "native-amd64-required")


def validate(stdout: str, stderr: str, code: int, kind: str) -> dict:
    need(not stderr.strip(), "unexpected-native-stderr")
    need(len(stdout.encode("utf-8")) <= 65536, "native-output-bound")
    try:
        report = json.loads(stdout, object_pairs_hook=unique_object,
                            parse_constant=lambda _: (_ for _ in ()).throw(GateFailure("nonfinite-json")))
    except (ValueError, TypeError) as exc:
        raise GateFailure("native-json-invalid") from exc
    need(type(report) is dict and set(report) in (FIELDS, FIELDS | {"diagnostics"}), "native-json-schema")
    need(report["schema"] == "mycomputer-activation-stage1-v1" and
         report["scope"] == "mycomputer-registration-activation-only", "native-identity")
    need(type(report["code"]) is int and 0 <= report["code"] <= 0xFFFFFFFF, "hresult-shape")
    need(type(report["stage"]) is str and re.fullmatch(r"[a-z0-9-]{1,96}", report["stage"]) is not None, "stage-shape")
    need(type(report["preconditions"]) is dict and set(report["preconditions"]) == CONDITIONS, "precondition-shape")
    need(all(v is None or type(v) is bool for v in report["preconditions"].values()), "precondition-types")
    for field in ("cleanupVerified", "prerequisitesSatisfied", "brokerEditingVerified", "profileActivationApiVerified", "actualDllActivationVerified"):
        need(type(report[field]) is bool, "boolean-shape")
    need(report["writesStarted"] is None or type(report["writesStarted"]) is bool, "writes-shape")
    need(report["writesStarted"] is not True, "unexpected-write-attempt")
    need(report["publisherTrust"] == "not-established" and
         report["brokerEditingVerified"] is False and report["profileActivationApiVerified"] is False and
         report["actualDllActivationVerified"] is False, "unexpected-activation-claim")
    need(report["prerequisitesSatisfied"] is False and report["dllSha256"] is None and report["dllPresent"] is None, "unexpected-package-or-registration-readiness")
    need(report["actualHostName"] is None or type(report["actualHostName"]) is str, "hostname-shape")
    for field in ("threadLanguage", "currentLanguage"):
        need(report[field] is None or (type(report[field]) is int and 0 <= report[field] <= 0xFFFF), "language-shape")
    if kind == "preflight":
        need(report["mode"] == "preflight" and report["writesStarted"] is False and report["cleanupVerified"] is False, "preflight-scope")
        need(code == 0 and report["status"] == "checked" and report["stage"] == "completed" and report["code"] == 0, "preflight-real-queries-must-succeed")
        need(type(report["actualHostName"]) is str and bool(report["actualHostName"].strip()) and
             type(report["threadLanguage"]) is int and type(report["currentLanguage"]) is int,
             "preflight-actual-environment-not-observed")
        need(report["preconditions"]["nativeX64"] is True and report["preconditions"]["identityAbsent"] is True and
             report["preconditions"]["directTestAbsent"] is True and
             all(type(report["preconditions"][key]) is bool for key in CONDITIONS - {"dllVerified"}) and
             report["preconditions"]["dllVerified"] is None, "preflight-required-query-facts")
    elif kind == "verify":
        need(report["mode"] == "verify" and report["writesStarted"] is False, "verify-scope")
        need((code == 0 and report["status"] == "pass" and report["cleanupVerified"] is True and report["stage"] == "completed") or
             (code == 3 and report["status"] == "blocked" and report["stage"] == "mycomputer-host-required" and
              report["cleanupVerified"] is False), "verify-result")
    elif kind == "invalid":
        need(code == 3 and report["mode"] == "invalid" and report["status"] == "blocked" and
             report["stage"] == "arguments" and report["writesStarted"] is False and report["cleanupVerified"] is False, "invalid-argument-result")
    else:
        need(kind in ("missing", "malformed"), "unknown-test-case")
        stages = {"mycomputer-host-required", "ledger-file"} if kind == "missing" else {"mycomputer-host-required", "ledger-owner-decrypt"}
        need(code == 1 and report["mode"] == "recover" and report["status"] == "failed" and
             report["writesStarted"] is None and report["cleanupVerified"] is False and report["stage"] in stages,
             "unsafe-or-unexpected-recovery-rejection")
    return report


def run_checks(exe: Path, results: list[dict]) -> list[dict]:
    require_windows_x64()
    need(exe.is_file() and exe.name == "YimeMyComputerActivationStage1.exe", "expected-executable-required")
    with tempfile.TemporaryDirectory(prefix="yime-stage1-negative-") as raw:
        directory = Path(raw)
        ledger = directory / "registration-ledger.dpapi"
        cases = [
            ("default-preflight", [], "preflight"),
            ("explicit-preflight", ["--preflight"], "preflight"),
            ("readonly-verify", ["--verify"], "verify"),
            ("invalid-arguments", ["--unsupported-stage1-mode"], "invalid"),
            ("missing-ledger-rejected", ["--recover", "--ledger", str(ledger), "--expected-ledger-sha256", "0" * 64], "missing"),
            ("malformed-ledger-rejected", ["--recover", "--ledger", str(ledger), "--expected-ledger-sha256", hashlib.sha256(BAD_LEDGER).hexdigest()], "malformed"),
        ]
        for name, args, kind in cases:
            if kind == "malformed":
                ledger.write_bytes(BAD_LEDGER)
            start = time.monotonic()
            try:
                # No shell, no retry, no inherited test bypasses added or removed.
                completed = subprocess.run([str(exe), *args], cwd=directory, capture_output=True,
                                           text=True, encoding="utf-8", errors="strict", timeout=30,
                                           check=False, shell=False)
            except subprocess.TimeoutExpired as exc:
                raise GateFailure(f"{name}-timeout-no-retry") from exc
            try:
                report = validate(completed.stdout, completed.stderr, completed.returncode, kind)
            except GateFailure as failure:
                raise GateFailure(f"{name}:{failure}") from failure
            expected_files = {ledger.name} if kind == "malformed" else set()
            need({entry.name for entry in directory.iterdir()} == expected_files, "unexpected-test-directory-write")
            if kind == "malformed":
                need(ledger.read_bytes() == BAD_LEDGER, "malformed-ledger-was-modified")
            results.append({"case": name, "exitCode": completed.returncode, "status": report["status"],
                            "stage": report["stage"], "code": report["code"], "writesStarted": report["writesStarted"],
                            "elapsedSeconds": round(time.monotonic() - start, 3),
                            "earlierHostGate": report["stage"] == "mycomputer-host-required"})
    need(len(results) == 6, "mandatory-six-cases-not-completed")
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {"schema": "mycomputer-native-nonregistration-tests-v1", "status": "failed", "caseCount": 0,
              "cases": [], "registrationRequested": False, "validRecoveryRequested": False,
              "successfulActivationTested": False, "systemRegistryIndependentlyDiffed": False}
    try:
        run_checks(args.exe.resolve(), result["cases"])
        result["caseCount"] = len(result["cases"])
        result["exeSha256"] = hashlib.sha256(args.exe.read_bytes()).hexdigest()
        result["status"] = "passed"
    except (GateFailure, OSError, UnicodeError) as failure:
        result["error"] = str(failure) if isinstance(failure, GateFailure) else "native-test-process-or-file-error"
    result["caseCount"] = len(result["cases"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"status": result["status"], "caseCount": result["caseCount"], "error": result.get("error")}, ensure_ascii=False))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
