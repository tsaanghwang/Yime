"""One explicitly reviewed retry after the first Windows consent did not complete.

The original marker/logs and immutable package remain untouched. This wrapper
reserves a separate one-shot marker, while the original entry retains all of its
ordinary-token, package, native Check, current DLL-user and installer safeguards.
It never schedules itself, stops a process, changes an input profile or elevates.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import types
import uuid

ROOT = Path("C:/dev/Yime-deliveries/18u-binding-636cef68-20261106")
OLD_ROOT = Path("C:/Program Files/YimeCore 18u Touch")
PINS = {
    "run_18u_binding_install.py": "98b80e6ba5afe659714b9a0003f9a741c55a6cf5aa5332510bd0c778823ab218",
    "18u-standard-install-attempt.json": "f296f05ce31cc27b9f94b9102530aadaa873d7ff7f24d68a6ad5ccde5751e3c3",
    "18u-start-20261106T000831Z-903ec799.json": "23d95386db92a1047cd2c6d7221532de01cdf75fc1f07c7eac1a247e071b7b0c",
    "18u-start-20261106T000831Z-903ec799-native-install.log": "4eae8a7814bcd543bdcde27cdd6e14782646e786d8e7a6ebc9598dd64ae2eab1",
}
OLD_MANIFEST_SHA = "572f66e68ad91effbdc994c6fbe1ca71a705d7ee4c5194b10d41447480ad83f3"
RETRY_ATTEMPT = ROOT / "18u-standard-install-retry-01-attempt.json"

def digest(path):
    for member in (path, *path.parents):
        if member.is_symlink() or member.is_junction():
            raise RuntimeError("Reparse path refused: " + str(member))
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.dont_write_bytecode = True
    started = datetime.now(timezone.utc).isoformat()
    record_path = ROOT / ("18u-retry-01-review-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8] + ".json")
    record = {"schema": "18u-explicit-retry-01-v1", "startedUTC": started,
              "reason": "first Windows consent did not complete before maintenance; user is now ready to handle consent",
              "checkOnly": args.check, "originalAttemptPreserved": True,
              "retryAttempt": str(RETRY_ATTEMPT), "status": "started"}
    result = 1
    try:
        if Path(__file__).absolute().parent != ROOT:
            raise RuntimeError("Run from the fixed delivery directory.")
        for name, expected in PINS.items():
            if digest(ROOT / name) != expected:
                raise RuntimeError("Preserved prerequisite hash mismatch: " + name)
        if RETRY_ATTEMPT.exists() and not args.check:
            raise RuntimeError("This explicit retry was already attempted; preserve its evidence. No automatic retry.")
        manifest = OLD_ROOT / "installed-18u-product.json"
        if digest(manifest) != OLD_MANIFEST_SHA:
            raise RuntimeError("Installed state is no longer the reviewed .4 payload; no install launched.")
        files = json.loads(manifest.read_text(encoding="utf-8"))["files"]
        for row in files:
            relative = PurePosixPath(row["path"])
            if relative.is_absolute() or ".." in relative.parts or ":" in row["path"] or "\\" in row["path"]:
                raise RuntimeError("Invalid installed manifest path.")
            path = OLD_ROOT / row["path"]
            if path.stat().st_size != row["bytes"] or digest(path) != row["sha256"]:
                raise RuntimeError("Installed .4 payload changed: " + row["path"])
        record["oldPayloadFilesVerified"] = len(files)
        runner_path = ROOT / "run_18u_binding_install.py"
        runner_bytes = runner_path.read_bytes()
        if hashlib.sha256(runner_bytes).hexdigest() != PINS[runner_path.name]:
            raise RuntimeError("Original runner changed before loading.")
        entry = types.ModuleType("pinned_18u_entry")
        entry.__file__ = str(runner_path)
        exec(compile(runner_bytes, str(runner_path), "exec"), entry.__dict__)
        entry.require_ordinary_token()
        # New explicit attempt, not deletion or resetting of the original guard.
        entry.ATTEMPT = RETRY_ATTEMPT
        print("已保留首次取消记录；本次为独立的一次性标准安装重试。", flush=True)
        result = entry.main(["--check"] if args.check else [])
        record["status"] = "entry-returned-check-report-for-result"
    except Exception as exc:
        record["status"] = "stopped-before-original-entry"
        record["error"] = str(exc)
        print("停止：" + str(exc), flush=True)
    finally:
        record["finishedUTC"] = datetime.now(timezone.utc).isoformat()
        record["exitCode"] = result
        with record_path.open("x", encoding="utf-8") as stream:
            json.dump(record, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print("本次独立重试记录：" + str(record_path), flush=True)
    return result

if __name__ == "__main__":
    raise SystemExit(main())
