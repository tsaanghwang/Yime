#!/usr/bin/env python3
"""Verify that Win32 build dependencies are complete and usable offline."""

from __future__ import annotations

import hashlib
import json
import sys
import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CORROSION_ROOT = REPO_ROOT / "third_party" / "corrosion"
CORROSION_VERSION = "0.6.1"
CORROSION_COMMIT = "1499b14e4906a2890f5cee1547c8848db261753d"
CORROSION_TREE_SHA256 = "3c01b36b86b3b9e0997903a1b0e885d2ae893083c19131b11647540718800864"
CARGO_ROOT = REPO_ROOT / "PIMELauncher"
CARGO_LOCK = CARGO_ROOT / "Cargo.lock"
CARGO_VENDOR = CARGO_ROOT / "vendor"
GO_WINRES_ROOT = REPO_ROOT / "third_party" / "go-winres"
GO_WINRES_VERSION = "0.3.3"
GO_WINRES_TREE_SHA256 = "727e8eca52890e48f10fc41dfda6b8a2a7899e308e80e1f8937678df452e9dea"


class VerificationError(RuntimeError):
    """Raised when a vendored dependency differs from its locked identity."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_identity(root: Path) -> tuple[str, int, int]:
    if not root.is_dir():
        raise VerificationError(f"missing vendored dependency directory: {root}")
    digest = hashlib.sha256()
    count = 0
    total_bytes = 0
    files = sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    for path in files:
        relative = path.relative_to(root).as_posix()
        size = path.stat().st_size
        digest.update(f"{relative}\0{size}\0{sha256(path)}\n".encode("utf-8"))
        count += 1
        total_bytes += size
    return digest.hexdigest(), count, total_bytes


def verify_corrosion() -> tuple[int, int]:
    cmake_text = (CORROSION_ROOT / "CMakeLists.txt").read_text(encoding="utf-8")
    if f"VERSION {CORROSION_VERSION}" not in cmake_text:
        raise VerificationError(f"vendored Corrosion is not version {CORROSION_VERSION}")
    identity, count, total_bytes = tree_identity(CORROSION_ROOT)
    if identity != CORROSION_TREE_SHA256:
        raise VerificationError(
            "vendored Corrosion tree mismatch: "
            f"expected {CORROSION_TREE_SHA256}, got {identity}"
        )
    return count, total_bytes


def verify_go_winres() -> tuple[int, int]:
    go_mod = (GO_WINRES_ROOT / "go.mod").read_text(encoding="utf-8")
    if "module github.com/tc-hib/go-winres" not in go_mod:
        raise VerificationError("vendored go-winres module identity mismatch")
    modules = (GO_WINRES_ROOT / "vendor" / "modules.txt").read_text(
        encoding="utf-8"
    )
    for dependency in (
        "github.com/tc-hib/winres v0.2.1",
        "github.com/urfave/cli/v2 v2.25.7",
        "golang.org/x/image v0.12.0",
    ):
        if dependency not in modules:
            raise VerificationError(
                f"vendored go-winres dependency is missing: {dependency}"
            )
    identity, count, total_bytes = tree_identity(GO_WINRES_ROOT)
    if identity != GO_WINRES_TREE_SHA256:
        raise VerificationError(
            "vendored go-winres tree mismatch: "
            f"expected {GO_WINRES_TREE_SHA256}, got {identity}"
        )
    return count, total_bytes


def locked_registry_packages() -> dict[str, tuple[str, str]]:
    lock = tomllib.loads(CARGO_LOCK.read_text(encoding="utf-8"))
    result: dict[str, tuple[str, str]] = {}
    for package in lock.get("package", []):
        source = str(package.get("source", ""))
        if not source.startswith("registry+"):
            continue
        checksum = str(package.get("checksum", ""))
        if len(checksum) != 64:
            raise VerificationError(
                f"locked registry package has no SHA-256: {package.get('name')}"
            )
        identity = (str(package["name"]), str(package["version"]))
        if checksum in result:
            raise VerificationError(f"duplicate Cargo package checksum: {checksum}")
        result[checksum] = identity
    return result


def verify_cargo_vendor() -> tuple[int, int, int]:
    expected = locked_registry_packages()
    if not CARGO_VENDOR.is_dir():
        raise VerificationError(f"missing Cargo vendor directory: {CARGO_VENDOR}")

    found: dict[str, Path] = {}
    verified_files = 0
    verified_bytes = 0
    for directory in sorted(path for path in CARGO_VENDOR.iterdir() if path.is_dir()):
        checksum_path = directory / ".cargo-checksum.json"
        if not checksum_path.is_file():
            raise VerificationError(f"vendored crate has no checksum manifest: {directory.name}")
        payload = json.loads(checksum_path.read_text(encoding="utf-8"))
        package_checksum = str(payload.get("package", ""))
        if package_checksum not in expected:
            raise VerificationError(
                f"vendored crate is not present in Cargo.lock: {directory.name}"
            )
        if package_checksum in found:
            raise VerificationError(
                f"duplicate vendored crate for checksum {package_checksum}: {directory.name}"
            )
        files = payload.get("files")
        if not isinstance(files, dict) or not files:
            raise VerificationError(f"invalid checksum file list: {directory.name}")

        expected_paths = set(files)
        actual_paths = {
            path.relative_to(directory).as_posix()
            for path in directory.rglob("*")
            if path.is_file() and path.name != ".cargo-checksum.json"
        }
        if actual_paths != expected_paths:
            missing = sorted(expected_paths - actual_paths)
            extra = sorted(actual_paths - expected_paths)
            raise VerificationError(
                f"vendored crate file set mismatch for {directory.name}: "
                f"missing={missing[:3]}, extra={extra[:3]}"
            )
        for relative, expected_digest in files.items():
            path = directory / Path(relative)
            actual_digest = sha256(path)
            if actual_digest != expected_digest:
                raise VerificationError(
                    f"vendored crate file hash mismatch: {directory.name}/{relative}"
                )
            verified_files += 1
            verified_bytes += path.stat().st_size
        found[package_checksum] = directory

    missing_packages = set(expected) - set(found)
    if missing_packages:
        identities = [expected[checksum] for checksum in sorted(missing_packages)]
        raise VerificationError(f"Cargo.lock packages missing from vendor: {identities[:5]}")
    return len(found), verified_files, verified_bytes


def main() -> int:
    try:
        corrosion_files, corrosion_bytes = verify_corrosion()
        crates, crate_files, crate_bytes = verify_cargo_vendor()
        go_winres_files, go_winres_bytes = verify_go_winres()
    except (OSError, ValueError, KeyError, VerificationError) as exc:
        print(f"FAIL vendored build dependencies: {exc}", file=sys.stderr)
        return 1
    print(
        "PASS vendored build dependencies: "
        f"Corrosion v{CORROSION_VERSION} commit {CORROSION_COMMIT} "
        f"({corrosion_files} files, {corrosion_bytes} bytes); "
        f"{crates} Cargo crates ({crate_files} files, {crate_bytes} bytes); "
        f"go-winres v{GO_WINRES_VERSION} "
        f"({go_winres_files} files, {go_winres_bytes} bytes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
