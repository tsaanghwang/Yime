"""Verify this fresh standalone YimeCore delivery without executing its binaries.

Run after source build and simple packaging. ZIP verification is optional and
checks a previously created archive; this program never builds or archives.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import struct
import subprocess
import zipfile


REPO = Path(__file__).resolve().parents[2]
DELIVERY = Path(r"C:\dev\Yime-deliveries\registration-fix-20260929")
VERSION = "0.1.0-local.13-registration-fix-20260929"
MODES = ("full", "variable", "shorthand")
ARCHITECTURES = ("x64", "x86")


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def plain_path(path: Path) -> Path:
    path = path.absolute()
    for component in (path, *path.parents):
        require(not component.is_symlink() and not component.is_junction(), f"Indirect path: {component}")
    return path


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def record(path: Path, relative: str) -> dict:
    plain_path(path)
    require(path.is_file(), f"Missing regular file: {path}")
    return {"path": relative, "bytes": path.stat().st_size, "sha256": sha256(path)}


def read(path: Path):
    plain_path(path)
    return json.loads(path.read_text(encoding="utf-8-sig"))


def canonical_relative(name: str) -> PurePosixPath:
    require(isinstance(name, str) and bool(name), "Empty/non-string manifest path")
    path = PurePosixPath(name)
    require(not path.is_absolute() and "\\" not in name and ":" not in name, f"Non-relative path: {name}")
    require(all(part and part not in (".", "..") and not part.endswith((".", " ")) for part in name.split("/")), f"Non-canonical path: {name}")
    return path


def file_inventory(root: Path) -> dict[str, dict]:
    plain_path(root)
    result = {}
    folded = set()
    for path in sorted(root.rglob("*")):
        plain_path(path)
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        canonical_relative(relative)
        require(relative.casefold() not in folded, f"Case-insensitive file collision: {relative}")
        folded.add(relative.casefold())
        result[relative] = record(path, relative)
    return result


def manifest_inventory(rows: list, label: str) -> dict[str, dict]:
    require(isinstance(rows, list), f"Non-list {label}")
    result = {}
    folded = set()
    for row in rows:
        require(set(row) == {"path", "bytes", "sha256"}, f"Unexpected {label} record keys")
        name = row["path"]
        canonical_relative(name)
        require(name.casefold() not in folded, f"Duplicate {label} path: {name}")
        require(isinstance(row["bytes"], int) and row["bytes"] >= 0, f"Invalid {label} byte count")
        require(re.fullmatch("[0-9a-f]{64}", row["sha256"]) is not None, f"Invalid {label} digest")
        folded.add(name.casefold())
        result[name] = row
    return result


def pe_machine(path: Path) -> int:
    with path.open("rb") as stream:
        require(stream.read(2) == b"MZ", f"Missing MZ header: {path}")
        stream.seek(0x3C)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        require(stream.read(4) == b"PE\0\0", f"Missing PE header: {path}")
        return struct.unpack("<H", stream.read(2))[0]


def committed_record(repo: Path, commit: str, relative: str) -> dict:
    # Git stores LF blobs while these installer files use CRLF in the checkout.
    # Preserve both identities; compare package bytes to the checkout projection.
    identity = f"{commit}:{relative}"
    blob = subprocess.check_output(["git", "cat-file", "blob", identity], cwd=repo)
    projected = subprocess.check_output(["git", "cat-file", "--filters", identity], cwd=repo)
    return {
        "source_path": relative, "source_commit": commit,
        "git_blob_sha256": hashlib.sha256(blob).hexdigest(),
        "checkout_projection_sha256": hashlib.sha256(projected).hexdigest(),
        "projection": "git cat-file --filters applies the repository checkout attributes, including LF-to-CRLF conversion",
    }


def verify_package(repo: Path, build: Path, package: Path, commit: str) -> dict:
    require(re.fullmatch("[0-9a-f]{40}", commit) is not None, "Provide the full source commit SHA")
    current_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    require(current_head == commit, "Current worktree HEAD differs from the source fix commit")
    source_manifest_path = build / "package/build/source-manifest.json"
    source = read(source_manifest_path)
    build_manifest = read(build / "package/package-manifest.json")
    build_inputs = read(build / "package/build/build-inputs.json")
    summary = read(build / "summary.json")
    require(source["git_commit"] == build_manifest["git_commit"] == commit, "Build source commit differs from the requested fix commit")
    require(source["dirty"] is False, "Source build must be bound to a clean fix commit")
    require(summary["passed"] is True and summary["registration_and_default_preserved"] is True and summary["installable"] is True, "Source build/protection gates did not pass")
    require(build_manifest["source_manifest_sha256"] == build_inputs["source_manifest_sha256"] == sha256(source_manifest_path), "Source manifest binding mismatch")
    source_records = manifest_inventory(source["files"], "source manifest")
    for name, expected in source_records.items():
        require(record(repo / canonical_relative(name), name) == expected, f"Source changed since build: {name}")
    require(build_inputs["source_archive_sha256"] == sha256(build / "source-snapshot.zip"), "Build source snapshot digest mismatch")
    require(build_inputs["indexes_rebuilt_byte_identical"] is True, "Deterministic index gate missing")

    manifest = read(package / "product-package.json")
    require(manifest["format"] == "yime-simple-package-1" and manifest["product"] == "yimecore", "Wrong package format or product")
    require(manifest["version"] == VERSION, "Package identity does not distinguish the registration fix")
    expected = manifest_inventory(manifest["files"], "product manifest")
    actual = file_inventory(package / "payload")
    require(actual == expected, "Payload file set, byte count, or SHA-256 differs from product manifest")
    descriptor = read(package / "payload/local-product.json")
    require(descriptor["identity"]["clsid"] == "{E40FA752-BB96-461D-A51D-F40EB437EC65}", "Not the current product CLSID")
    require(descriptor["identity"]["profile"] == "{126F54C6-E9B1-4E22-8652-03224CBD49F9}", "Not the current product profile")
    require(descriptor == read(repo / "tools/yimecore/local-product.json"), "Packaged descriptor differs from current source")
    required = {row["path"] for row in descriptor["go_binaries"] + descriptor["assets"]}
    required |= {f"{arch}/{name}" for arch in ARCHITECTURES for name in descriptor["native_binaries"]}
    required |= {f"indexes/{mode}.yidx" for mode in MODES}
    required |= {"local-product.json", "speech-capability.json", "speech/product.json", "speech/admission.json", "speech/forward-source.json", "speech/admitted-records.json"}
    required |= {f"speech/indexes/{mode}-{kind}.yidx" for mode in MODES for kind in ("core", "stage5c")}
    require(len(expected) == 65 and set(expected) == required, "Package is not the exact complete 65-file descriptor payload")
    raw_records = manifest_inventory(build_manifest["files"], "raw build manifest")
    source_mapping = []
    pe = []
    for name, row in expected.items():
        raw = build / "package" / canonical_relative(name)
        require(raw_records.get(name) == row and record(raw, name) == row, f"Payload differs from fresh build: {name}")
        source_mapping.append({**row, "source_path": str(raw)})
        if Path(name).suffix.lower() in (".exe", ".dll"):
            arch = "x86" if name.startswith("x86/") else "x64"
            machine = pe_machine(package / "payload" / name)
            require(machine == {"x86": 0x14C, "x64": 0x8664}[arch], f"Wrong PE architecture: {name}")
            pe.append({"path": name, "architecture": arch, "machine": f"0x{machine:04x}"})
    require(len(pe) == 25, "Expected 25 current-built PE payload files")
    for asset in descriptor["assets"]:
        require(sha256(repo / asset["source"]) == expected[asset["path"]]["sha256"], f"Asset source mismatch: {asset['path']}")

    native_mapping = []
    query_regressions = []
    for arch in ARCHITECTURES:
        for name in descriptor["native_binaries"]:
            native = build / f"native-{arch}/Release" / name
            key = f"{arch}/{name}"
            require(record(native, key) == expected[key], f"Packaged native file differs from this build's Release: {key}")
            native_mapping.append({**expected[key], "source_path": str(native)})
        log_name = f"native-registration-query-{arch}.txt"
        fixture_path = build / (log_name + ".fixture.json")
        fixture = read(fixture_path)
        fixture_tool = build / f"native-{arch}/Release/YimeRegistrationQueryTests.exe"
        require(Path(fixture["executable"]) == fixture_tool, f"Wrong registration regression executable: {arch}")
        require(all(fixture[key] is True for key in ("environment_isolated", "environment_restored", "executed", "passed")) and fixture["exit_code"] == 0, f"Registration-query regression did not pass: {arch}")
        require(pe_machine(fixture_tool) == {"x86": 0x14C, "x64": 0x8664}[arch], f"Wrong regression PE architecture: {arch}")
        query_regressions.append({"architecture": arch, "passed": True, "log": record(build / log_name, log_name), "fixture": record(fixture_path, fixture_path.name), "test_executable": record(fixture_tool, f"native-{arch}/Release/YimeRegistrationQueryTests.exe")})

    installer_sources = []
    for name in ("Setup.ps1", "Setup.cmd", "Product.psm1"):
        row = record(package / name, name)
        relative = f"installer/simple/{name}"
        committed = committed_record(repo, commit, relative)
        require(row["sha256"] == sha256(repo / relative) == committed["checkout_projection_sha256"], f"Installer source/commit mismatch: {name}")
        installer_sources.append({**row, **committed})
    build_script = "installer/simple/Build-Package.ps1"
    packager_source = committed_record(repo, commit, build_script)
    require(sha256(repo / build_script) == packager_source["checkout_projection_sha256"], "Simple packager changed after fix commit")
    package_files = file_inventory(package)
    return {
        "schema_version": "yimecore-registration-fix-package-verification-v1",
        "verified_utc": datetime.now(timezone.utc).isoformat(), "passed": True,
        "source_commit": commit, "source_manifest_dirty": source["dirty"],
        "source_manifest": record(source_manifest_path, "build/source-manifest.json"),
        "build_root": str(build), "package_root": str(package), "product": "yimecore",
        "package_version": VERSION, "descriptor_version": descriptor["version"],
        "payload_files": len(expected), "payload_bytes": sum(row["bytes"] for row in expected.values()),
        "product_manifest": record(package / "product-package.json", "product-package.json"),
        "pe_files": pe, "native_source_mapping": native_mapping,
        "registration_query_regressions": query_regressions,
        "installer_sources": installer_sources, "packager_source": packager_source,
        "payload_source_mapping": source_mapping,
        "package_files": list(package_files.values()),
        "installed_product_used_as_input": False, "installed_product_mutated": False,
        "registered_host_executed": False, "input_acceptance_claimed": False,
    }


def verify_zip(archive: Path, package: Path, prefix: str) -> dict:
    canonical_relative(prefix)
    require("/" not in prefix, "ZIP prefix must be the single package-root directory name")
    files = file_inventory(package)
    expected = {f"{prefix}/{name}": row for name, row in files.items()}
    rows = []
    with zipfile.ZipFile(archive) as zipped:
        all_names = set()
        folded = set()
        seen_files = set()
        for item in zipped.infolist():
            name = item.filename
            canonical_relative(name.rstrip("/") if item.is_dir() else name)
            require(name not in all_names and name.casefold() not in folded, f"Duplicate ZIP member: {name}")
            all_names.add(name)
            folded.add(name.casefold())
            require(not (item.flag_bits & 1), "Encrypted ZIP members are not supported")
            if item.is_dir():
                require(any(key.startswith(name) for key in expected), f"Unexpected ZIP directory: {name}")
                continue
            require(name in expected, f"Unexpected ZIP member: {name}")
            require(item.file_size == expected[name]["bytes"], f"ZIP member size mismatch: {name}")
            with zipped.open(item) as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            require(digest == expected[name]["sha256"], f"ZIP member SHA-256 mismatch: {name}")
            rows.append({"path": name, "bytes": item.file_size, "sha256": digest, "crc32": f"{item.CRC:08x}"})
            seen_files.add(name)
        require(seen_files == set(expected), "ZIP exact file set differs from completed package")
        require(zipped.testzip() is None, "ZIP CRC validation failed")
    return {"schema_version": "yimecore-registration-fix-zip-verification-v1", "passed": True,
            "verified_utc": datetime.now(timezone.utc).isoformat(), "archive": record(archive, archive.name),
            "package_root": str(package), "zip_prefix": prefix, "file_count": len(rows), "files": rows}


def write_report(path: Path, value: dict) -> None:
    plain_path(path)
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=REPO)
    parser.add_argument("--build-root", type=Path, default=REPO / ".tmp/yimecore-local-product/r")
    parser.add_argument("--package-root", type=Path, default=DELIVERY / "YimeCore-Registration-Fix-20260929")
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--zip", type=Path)
    parser.add_argument("--zip-prefix")
    parser.add_argument("--zip-report", type=Path)
    args = parser.parse_args()
    require(not args.report.exists(), "Preserve prior package verification report")
    require(bool(args.zip) == bool(args.zip_report), "Provide --zip and --zip-report together")
    require(not args.zip_report or not args.zip_report.exists(), "Preserve prior ZIP verification report")
    repo, build, package = (plain_path(path) for path in (args.repo, args.build_root, args.package_root))
    result = verify_package(repo, build, package, args.expected_commit)
    zip_result = verify_zip(plain_path(args.zip), package, args.zip_prefix or package.name) if args.zip else None
    write_report(args.report, result)
    if zip_result:
        write_report(args.zip_report, zip_result)
    print(json.dumps({"passed": True, "payload_files": result["payload_files"], "pe_files": len(result["pe_files"]), "report": str(args.report), "zip_report": str(args.zip_report) if args.zip_report else None}))


if __name__ == "__main__":
    main()
