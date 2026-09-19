"""Read only expected installed payloads and targeted HKLM registration.

This audits installed static consistency, not package recovery, reproducible
builds, process health, registration activation, or live input acceptance.
Product executables and DLLs are never invoked. The only child command is
``go version -m <file>``, which reads Go build information from each EXE.
Supply --output with a new directory; existing evidence is never overwritten.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PureWindowsPath
import winreg


REPORT = Path(__file__).resolve().parent
METADATA = REPORT / "raw" / "retained-metadata"
OUTPUT: Path
PRODUCTS = {
    "yimecore": {
        "root": Path("C:/Program Files/YimeCore"),
        "clsid": "{E40FA752-BB96-461D-A51D-F40EB437EC65}",
        "manifest_sha256": "67cbdf516ae8e4348f47ffa5bc7d94d1468d200c320b66b4a1d73ce649facf8d",
        "expected_files": 65,
    },
    "rime-pime": {
        "root": Path("C:/Program Files/Yime Rime-PIME"),
        "clsid": "{35F67E9D-A54D-4177-9697-8B0AB71A9E04}",
        "manifest_sha256": "2996982b88c70b251124847fd6fa37ada185a6c173de1139cbb32afda8324d38",
        "expected_files": 160,
    },
}


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(name: str, value: object) -> None:
    # The output filename is fixed by this script, never supplied by a manifest.
    target = OUTPUT / name
    if target.parent != OUTPUT or target.is_symlink():
        raise ValueError("Unsafe audit output")
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def plain_path(path: Path) -> None:
    """Reject symlinks/junctions without following them into unrelated data."""
    for part in [path, *path.parents]:
        info = part.lstat()
        if info.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            raise ValueError(f"Reparse point is outside audit scope: {part}")


def member_path(root: Path, name: object) -> Path:
    if not isinstance(name, str) or not name:
        raise ValueError("Empty or non-string package member")
    relative = PureWindowsPath(name)
    parts = re.split(r"[/\\]", name)
    if relative.is_absolute() or relative.drive or relative.root or ":" in name:
        raise ValueError(f"Rooted or stream member: {name}")
    reserved = re.compile(r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)", re.I)
    if any(not p or p in (".", "..") or p.endswith((".", " "))
           or reserved.match(p) or any(ord(c) < 32 or c in '<>\"|?*' for c in p)
           for p in parts):
        raise ValueError(f"Unsafe member: {name}")
    target = root.joinpath(*parts)
    if not target.is_relative_to(root):
        raise ValueError(f"Member escaped root: {name}")
    return target


def registry_value(value: object) -> object:
    if isinstance(value, bytes):
        return {"encoding": "hex", "value": value.hex()}
    return value


def registry_tree(key_path: str, view: int, depth: int = 0) -> dict:
    if depth > 16:
        return {"error": "Maximum targeted registration depth exceeded"}
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key_path, 0,
                           winreg.KEY_READ | view) as key:
            subkeys, values, last_write = winreg.QueryInfoKey(key)
            raw_values = []
            for index in range(values):
                name, data, kind = winreg.EnumValue(key, index)
                raw_values.append({"name": name, "type": kind, "data": registry_value(data)})
            child_names = [winreg.EnumKey(key, index) for index in range(subkeys)]
        return {
            "present": True,
            "last_write_100ns_since_1601": last_write,
            "values": sorted(raw_values, key=lambda row: row["name"].casefold()),
            "subkeys": {child: registry_tree(key_path + "\\" + child, view, depth + 1)
                        for child in sorted(child_names, key=str.casefold)},
        }
    except FileNotFoundError:
        return {"present": False}
    except OSError as exc:
        return {"error": str(exc), "winerror": exc.winerror}


def registry_snapshot() -> dict:
    entries = []
    for product, settings in PRODUCTS.items():
        for architecture, view in (("x64", winreg.KEY_WOW64_64KEY),
                                   ("x86", winreg.KEY_WOW64_32KEY)):
            for kind, prefix in (("CLSID", "SOFTWARE\\Classes\\CLSID\\"),
                                 ("TIP", "SOFTWARE\\Microsoft\\CTF\\TIP\\")):
                path = prefix + settings["clsid"]
                entries.append({"product": product, "architecture": architecture,
                                "kind": kind, "hive": "HKEY_LOCAL_MACHINE", "path": path,
                                "tree": registry_tree(path, view)})
    encoded = json.dumps(entries, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return {"collected_at_utc": now(), "mutation_performed": False,
            "entries_sha256": hashlib.sha256(encoded).hexdigest(), "entries": entries}


def registry_read_success(snapshot: dict) -> bool:
    def tree_read(node: dict) -> bool:
        return node.get("present") is True and "error" not in node and all(
            tree_read(child) for child in node.get("subkeys", {}).values())
    return len(snapshot["entries"]) == 8 and all(
        tree_read(entry["tree"]) for entry in snapshot["entries"])


def go_build_info(go: str, path: Path) -> dict:
    command = [go, "version", "-m", str(path)]
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=30,
                                creationflags=subprocess.CREATE_NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"command": command, "error": str(exc), "product_binary_executed": False}
    settings = {}
    module_path = None
    for line in result.stdout.splitlines():
        if line.startswith("\tbuild\t"):
            setting = line.removeprefix("\tbuild\t")
            key, separator, value = setting.partition("=")
            if separator:
                settings[key] = value
        elif line.startswith("\tpath\t"):
            module_path = line.removeprefix("\tpath\t")
    return {"command": command, "exit_code": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr,
            "go_metadata_present": module_path is not None,
            "module_path": module_path, "settings": settings,
            "vcs_revision": settings.get("vcs.revision"),
            "vcs_modified": settings.get("vcs.modified"),
            "vcs_status": "present" if "vcs.revision" in settings else "not embedded",
            "product_binary_executed": False}


def audit_product(product: str, settings: dict, go: str) -> dict:
    manifest_path = METADATA / f"{product}-manifest.json"
    manifest_hash = digest(manifest_path)
    if manifest_hash != settings["manifest_sha256"]:
        raise ValueError(f"Historical manifest SHA-256 mismatch: {product}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if manifest["format"] != "yime-simple-package-1" or manifest["product"] != product:
        raise ValueError(f"Unexpected manifest identity: {product}")
    if len(manifest["files"]) != settings["expected_files"]:
        raise ValueError(f"Unexpected historical file count: {product}")
    root = settings["root"]
    plain_path(root)
    seen = set()
    rows = []
    # Validate the whole manifest before opening any installed member.
    for row in manifest["files"]:
        target = member_path(root, row["path"])
        identity = str(target).casefold()
        if identity in seen:
            raise ValueError(f"Duplicate Windows member: {row['path']}")
        seen.add(identity)
        if type(row["bytes"]) is not int or row["bytes"] < 0:
            raise ValueError("Invalid expected byte length")
        if not re.fullmatch(r"[0-9a-f]{64}", row["sha256"]):
            raise ValueError("Invalid expected SHA-256")
        rows.append((row, target))
    checks = []
    build_info = []
    for expected, target in rows:
        checked = {"path": expected["path"], "expected_bytes": expected["bytes"],
                   "expected_sha256": expected["sha256"]}
        try:
            plain_path(target)
            before = target.stat()
            if not stat.S_ISREG(before.st_mode):
                raise ValueError("Expected a regular file")
            observed_hash = digest(target)
            after = target.stat()
            stable = (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns)
            checked.update({"actual_bytes": after.st_size, "actual_sha256": observed_hash,
                            "stable_while_read": stable,
                            "match": stable and after.st_size == expected["bytes"]
                                     and observed_hash == expected["sha256"]})
            if target.suffix.casefold() == ".exe":
                build_info.append({"path": expected["path"], "file_sha256": observed_hash,
                                   **go_build_info(go, target)})
        except (OSError, ValueError) as exc:
            checked.update({"match": False, "error": str(exc)})
        checks.append(checked)
    return {"product": product, "install_root": str(root),
            "historical_manifest_sha256": manifest_hash,
            "historical_manifest_hash_matches": True, "safe_unique_paths": True,
            "expected_files": len(checks), "matched_files": sum(row["match"] for row in checks),
            "mismatch_count": sum(not row["match"] for row in checks),
            "unlisted_installed_files_enumerated": False,
            "expected_file_checks": checks, "executable_build_info": build_info}


def main() -> int:
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    OUTPUT = args.output.resolve()
    if sys.platform != "win32":
        raise SystemExit("This report audit requires Windows")
    OUTPUT.mkdir(parents=True, exist_ok=False)
    plain_path(OUTPUT)
    before = registry_snapshot()
    write_json("registration-before.json", before)
    products = []
    error = None
    try:
        go = shutil.which("go")
        if not go:
            raise RuntimeError("go is required only to read build metadata")
        for product, settings in PRODUCTS.items():
            result = audit_product(product, settings, go)
            write_json(f"{product}-payload.json", result)
            products.append(result)
    except (OSError, ValueError, RuntimeError, KeyError) as exc:
        error = str(exc)
    after = registry_snapshot()
    write_json("registration-after.json", after)
    unchanged = before["entries"] == after["entries"]
    registration_readable = registry_read_success(before) and registry_read_success(after)
    summary = {
        "schema_version": "yime-installed-static-read-audit-v1", "completed_at_utc": now(),
        "script_sha256": digest(Path(__file__)), "error": error,
        "product_mutation_performed": False, "product_binary_executed": False,
        "user_state_read": False, "registry_mutation_performed": False,
        "registration_roots_present_and_readable": registration_readable,
        "registration_snapshot_unchanged": unchanged,
        "registration_before_sha256": before["entries_sha256"],
        "registration_after_sha256": after["entries_sha256"],
        "products": [{key: product[key] for key in (
            "product", "historical_manifest_sha256", "historical_manifest_hash_matches",
            "safe_unique_paths", "expected_files", "matched_files", "mismatch_count")}
                     | {"go_binaries": sum(info.get("go_metadata_present", False)
                                           for info in product["executable_build_info"]),
                        "go_vcs_revision_embedded": sorted({info["vcs_revision"]
                            for info in product["executable_build_info"]
                            if info.get("vcs_revision")})} for product in products],
        "boundary": "Installed expected-payload static consistency and selected HKLM registration preservation only. Does not recover the original package or prove build reproducibility, activation, running processes, startup, live input, or a clean source checkout. No user-state paths were enumerated. Native binaries are not assigned Go VCS metadata.",
    }
    write_json("summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if not error and unchanged and registration_readable and len(products) == 2 and all(
        product["mismatch_count"] == 0 for product in products) else 1


if __name__ == "__main__":
    raise SystemExit(main())
