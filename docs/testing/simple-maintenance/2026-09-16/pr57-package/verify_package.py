#!/usr/bin/env python3
"""Read-only independent verification of this PR #57 dual-product delivery.

Reads package/source/build files and PE headers. Does not execute package tools,
touch registry/user state, or install/uninstall/start/stop either product.
Only --output is written (it must not already exist).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def plain(path: Path) -> Path:
    path = path.absolute()
    for part in (path, *path.parents):
        if part.exists() or part.is_symlink():
            info = part.lstat()
            assert not part.is_symlink(), f"Linked path rejected: {part}"
            assert not getattr(info, "st_file_attributes", 0) & 0x400, (
                f"Reparse point rejected: {part}"
            )
    return path


def relative(value: str) -> str:
    assert isinstance(value, str) and value, "Empty/non-string member path"
    assert "\\" not in value and ":" not in value, f"Non-canonical member: {value!r}"
    assert not PurePosixPath(value).is_absolute(), f"Absolute member: {value!r}"
    pieces = value.split("/")
    reserved = re.compile(r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)", re.I)
    for piece in pieces:
        assert piece not in ("", ".", ".."), f"Unsafe member: {value!r}"
        assert not piece.endswith((" ", ".")), f"Windows alias path: {value!r}"
        assert not any(ord(c) < 32 or c in '<>\"|?*' for c in piece), (
            f"Invalid Windows member: {value!r}"
        )
        assert not reserved.match(piece), f"Reserved Windows member: {value!r}"
    return value


def member(root: Path, name: str) -> Path:
    name = relative(name)
    path = plain(root.joinpath(*name.split("/")))
    assert path.is_relative_to(root), f"Member escaped root: {name}"
    return path


def files(root: Path) -> dict[str, Path]:
    assert root.is_dir(), f"Directory missing: {root}"
    result = {}
    folded = set()
    for path in root.rglob("*"):
        plain(path)
        if path.is_dir():
            continue
        assert stat.S_ISREG(path.stat().st_mode), f"Non-regular file: {path}"
        name = relative(path.relative_to(root).as_posix())
        assert name.casefold() not in folded, f"Case alias: {name}"
        folded.add(name.casefold())
        result[name] = path
    return result


class Audit:
    def __init__(self, args):
        self.repo = plain(Path(args.repo))
        self.bundle = plain(Path(args.bundle))
        self.core_build = plain(Path(args.core_build))
        self.rime_build = plain(Path(args.rime_build))
        self.report = {
            "schema_version": "yime-pr57-independent-package-verification-v1",
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "scope": "File bytes, required payload, provenance bindings and PE machine headers only",
            "product_executables_executed": False,
            "installation_or_registry_modified": False,
            "live_user_data_read_or_modified": False,
            "installed_input_acceptance_claimed": False,
            "authenticode_verified": False,
            "inputs": {"repo": str(self.repo), "bundle": str(self.bundle),
                       "core_build": str(self.core_build), "rime_build": str(self.rime_build)},
            "checks": [], "products": {}, "errors": [],
        }
        self.products = {}

    def check(self, name, action):
        try:
            detail = action()
            self.report["checks"].append({"name": name, "passed": True, "detail": detail})
        except Exception as exc:
            self.report["checks"].append({"name": name, "passed": False})
            self.report["errors"].append({"check": name, "error": str(exc),
                                          "type": type(exc).__name__})

    @staticmethod
    def same(actual: Path, expected: Path):
        plain(actual)
        plain(expected)
        assert actual.is_file() and expected.is_file(), f"Missing comparison file: {actual} / {expected}"
        actual_hash = digest(actual)
        assert actual.stat().st_size == expected.stat().st_size and actual_hash == digest(expected), (
            f"File differs from expected source/build: {actual} != {expected}"
        )
        return {"bytes": actual.stat().st_size, "sha256": actual_hash}

    def package(self, product):
        root = member(self.bundle, product)
        path = root / "product-package.json"
        manifest = read_json(path)
        assert manifest["format"] == "yime-simple-package-1", "Unexpected package format"
        assert manifest["product"] == product, "Wrong product identity"
        assert isinstance(manifest.get("version"), str) and manifest["version"], "Version missing"
        assert isinstance(manifest["files"], list) and manifest["files"], "Manifest files missing"
        payload = plain(root / "payload")
        expected = {}
        folded = set()
        for row in manifest["files"]:
            name = relative(row["path"])
            assert name.casefold() not in folded, f"Duplicate manifest member: {name}"
            folded.add(name.casefold())
            assert type(row["bytes"]) is int and row["bytes"] >= 0, f"Invalid size: {name}"
            assert re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), f"Invalid SHA256: {name}"
            actual = member(payload, name)
            assert actual.is_file(), f"Missing payload: {name}"
            assert actual.stat().st_size == row["bytes"], f"Size mismatch: {name}"
            assert digest(actual) == row["sha256"], f"SHA256 mismatch: {name}"
            expected[name] = actual
        actual_files = files(payload)
        assert set(actual_files) == set(expected), (
            f"Unlisted/missing payload: extras={sorted(set(actual_files)-set(expected))}; "
            f"missing={sorted(set(expected)-set(actual_files))}"
        )
        self.products[product] = {"root": root, "payload": payload, "files": expected, "manifest": manifest}
        result = {"version": manifest["version"], "manifest_sha256": digest(path),
                  "file_count": len(expected), "total_bytes": sum(r["bytes"] for r in manifest["files"]),
                  "all_payload_sizes_and_sha256_verified": True, "no_unlisted_payload": True}
        self.report["products"][product] = result
        return result

    def installer_sources(self):
        result = {}
        source = self.repo / "installer/simple"
        for name in ("Install-Uninstall.cmd", "Manage-Products.ps1", "Choose-Products.ps1"):
            result[name] = self.same(self.bundle / name, source / name)
        for product in ("yimecore", "rime-pime"):
            for name in ("Setup.ps1", "Setup.cmd", "Product.psm1"):
                result[f"{product}/{name}"] = self.same(self.bundle / product / name, source / name)
        return result

    def core(self):
        package = self.products["yimecore"]
        payload = package["payload"]
        built = self.core_build / "package"
        descriptor_path = self.repo / "tools/yimecore/local-product.json"
        descriptor = read_json(descriptor_path)
        self.same(payload / "local-product.json", descriptor_path)
        assert descriptor["identity"]["clsid"] == "{E40FA752-BB96-461D-A51D-F40EB437EC65}", "Legacy core CLSID"
        assert descriptor["identity"]["profile"] == "{126F54C6-E9B1-4E22-8652-03224CBD49F9}", "Legacy core profile"
        assert descriptor["scope"]["active_architectures"] == ["x64", "x86"], "Unexpected core architecture scope"
        required = [b["path"] for b in descriptor["go_binaries"]]
        required += [f"{arch}/{name}" for arch in ("x64", "x86") for name in descriptor["native_binaries"]]
        required += [a["path"] for a in descriptor["assets"]]
        required += [f"indexes/{mode}.yidx" for mode in ("full", "variable", "shorthand")]
        speech = ["speech-capability.json", "speech/product.json", "speech/admission.json",
                  "speech/forward-source.json", "speech/admitted-records.json"]
        speech += [f"speech/indexes/{mode}-{kind}.yidx" for mode in ("full", "variable", "shorthand")
                   for kind in ("core", "stage5c")]
        assert len(speech) == 11
        required += speech + ["local-product.json"]
        for name in required:
            assert name in package["files"], f"Core required payload absent: {name}"
        for name, actual in package["files"].items():
            self.same(actual, member(built, name))
        for asset in descriptor["assets"]:
            self.same(member(payload, asset["path"]), member(self.repo, asset["source"]))
        actual_speech = {name for name in package["files"] if name.startswith("speech/") or name == "speech-capability.json"}
        assert actual_speech == set(speech), "Unexpected or missing speech payload files"
        assert set(package["files"]) == set(required), "Descriptor-derived complete core payload set differs"
        return {"descriptor_version": descriptor["version"], "identity": descriptor["identity"],
                "go_binaries": len(descriptor["go_binaries"]), "native_binaries": 2 * len(descriptor["native_binaries"]),
                "descriptor_assets": len(descriptor["assets"]), "normal_indexes": 3,
                "speech_payloads": len(speech), "required_files": sorted(required),
                "all_final_payload_matches_fresh_core_build": True,
                "all_descriptor_assets_match_current_repository": True}

    def core_provenance(self):
        built = self.core_build / "package"
        summary = read_json(self.core_build / "summary.json")
        assert summary["passed"] is True and summary["registration_and_default_preserved"] is True, "Core build/protection failed"
        inputs_path = built / "build/build-inputs.json"
        inputs = read_json(inputs_path)
        source_path = built / "build/source-manifest.json"
        source = read_json(source_path)
        assert digest(source_path) == inputs["source_manifest_sha256"], "Source manifest binding differs"
        archive = self.core_build / "source-snapshot.zip"
        assert digest(archive) == inputs["source_archive_sha256"], "Source archive binding differs"
        assert inputs["installed_package_used_as_input"] is False, "Installed runtime used as build input"
        assert inputs["indexes_rebuilt_byte_identical"] is True, "Core indexes not verified twice"
        assert source["dirty"] is False and not source["git_status"], "Core build did not start from clean source"
        manifest = read_json(built / "package-manifest.json")
        assert manifest["git_commit"] == source["git_commit"], "Core source commit mismatch"
        assert manifest["source_manifest_sha256"] == digest(source_path), "Core manifest source binding differs"
        speech = inputs["speech"]
        final = self.products["yimecore"]["payload"]
        assert digest(final / "speech-capability.json") == speech["capability_sha256"], "Speech capability binding differs"
        assert digest(final / "speech/product.json") == speech["product_manifest_sha256"], "Speech product binding differs"
        return {"git_commit": source["git_commit"], "source_manifest_sha256": digest(source_path),
                "source_archive_sha256": digest(archive), "build_inputs_sha256": digest(inputs_path),
                "source_dirty": source["dirty"], "installed_package_used_as_input": False,
                "indexes_rebuilt_byte_identical": True, "speech_binding": speech,
                "core_build_summary_sha256": digest(self.core_build / "summary.json")}

    def rime(self):
        package = self.products["rime-pime"]
        root = package["root"]
        payload = package["payload"]
        built = self.rime_build / "rime-pime"
        self.same(root / "product-package.json", built / "product-package.json")
        for name, actual in package["files"].items():
            self.same(actual, member(built / "payload", name))
        assert set(files(built / "payload")) == set(package["files"]), "Rime build payload set differs"
        required = ["PIMELauncher.exe", "backends.json"]
        required += [f"{arch}/{name}" for arch in ("x86", "x64")
                     for name in ("PIMETextService.dll", "PIMERegistrationStatus.exe")]
        tools = ["server", "tool-hub", "yime-trainer", "input-toolbar", "settings-tool", "diagnostics-tool",
                 "yime-layout-designer", "lexicon-manager", "reverse-lookup", "system-lexicon-audit",
                 "lexicon-promotion-scan", "blocklist-manager"]
        required += [f"go-backend/{name}.exe" for name in tools]
        base = "go-backend/input_methods/yime/"
        required += [base + name for name in ("ime.json", "rime_runtime.lock.json", "rime.dll", "rime_deployer.exe", "rime_dict_manager.exe")]
        data = ["default.yaml", "symbols.yaml", "essay.txt", "luna_pinyin.dict.yaml", "luna_pinyin.schema.yaml",
                "cangjie5.dict.yaml", "cangjie5.schema.yaml", "yime_lexicon_manifest.json", "yime_core_source_manifest.json",
                "yime_runtime_profile.json", "yime_pinyin_reverse_source.tsv", "yime_pinyin_codes.tsv",
                "yime_system_candidate_exclusions.tsv", "yime_yinyuan_layout.json", "yime_pua_pinyin.json",
                "pinyin_normalized.json", "fonts/YinYuan-Regular.ttf", "yime_erhua_reverse_source.tsv"]
        families = ("yime", "yime_erhua_mixed", "yime_erhua_mixed_sentence", "yime_sentence",
                    "yime_third_tone_stage5c", "yime_particle_a_stage6d", "yime_psc_peripheral", "yime_psc_peripheral_sentence")
        for family in families:
            data += [f"{family}_{mode}.dict.yaml" for mode in ("full", "variable", "shorthand")]
        for family in ("yime", "yime_erhua_mixed", "yime_psc_peripheral"):
            data += [f"{family}_{mode}.schema.yaml" for mode in ("full", "variable", "shorthand")]
        data += [f"{family}_manifest.json" for family in ("yime_erhua_mixed", "yime_third_tone_stage5c", "yime_particle_a_stage6d", "yime_psc_peripheral")]
        data += [f"trainer/{name}.json" for name in ("foundation", "curriculum", "yinyuan_catalog", "yinyuan_groups")]
        data += ["opencc/" + name for name in ("t2s.json", "s2t.json", "TSCharacters.ocd2", "STCharacters.ocd2")]
        required += [base + "data/" + name for name in data]
        for name in required:
            assert name in package["files"], f"Rime required payload absent: {name}"
        lock_path = self.repo / "go-backend/input_methods/yime/rime_runtime.lock.json"
        self.same(payload / base / "rime_runtime.lock.json", lock_path)
        lock = read_json(lock_path)
        assert lock["schema_version"] == 1 and lock["platform"] == "Windows-msvc-x64", "Unexpected Rime runtime lock"
        assert set(lock["files"]) == {"rime.dll", "rime_deployer.exe", "rime_dict_manager.exe"}, "Wrong locked runtime set"
        for name, expected in lock["files"].items():
            assert digest(payload / base / name) == expected.lower(), f"Pinned runtime SHA256 differs: {name}"
        source_assets = 0
        for name, actual in package["files"].items():
            if name.startswith(base):
                self.same(actual, member(self.repo, name))
                source_assets += 1
        forbidden = [name for name in package["files"] if name.endswith(".go") or "/brise/" in name
                     or "yime_core_trial." in name or name.endswith(".bak-32bit")]
        assert not forbidden, f"Retired/source payload leaked: {forbidden}"
        return {"required_files": sorted(required), "application_tools": len(tools),
                "pinned_runtime": lock, "lock_sha256": digest(lock_path),
                "all_final_payload_matches_rime_build": True,
                "repository_assets_byte_verified": source_assets}

    def pe_headers(self):
        result = []
        for product, package in self.products.items():
            for name, path in sorted(package["files"].items()):
                if path.suffix.lower() not in (".dll", ".exe"):
                    continue
                with path.open("rb") as stream:
                    header = stream.read(64)
                    assert len(header) == 64 and header[:2] == b"MZ", f"Invalid DOS header: {product}/{name}"
                    offset = struct.unpack_from("<I", header, 0x3C)[0]
                    assert 64 <= offset <= path.stat().st_size - 24, f"Invalid PE offset: {product}/{name}"
                    stream.seek(offset)
                    pe = stream.read(24)
                    assert pe[:4] == b"PE\0\0", f"Invalid PE signature: {product}/{name}"
                    machine = struct.unpack_from("<H", pe, 4)[0]
                expected = 0x14C if name.startswith("x86/") or (product == "rime-pime" and name == "PIMELauncher.exe") else 0x8664
                assert machine == expected, f"Wrong PE machine: {product}/{name}: {machine:#06x} expected {expected:#06x}"
                result.append({"product": product, "path": name, "machine": f"0x{machine:04x}",
                               "architecture": "x86" if machine == 0x14C else "x64"})
        assert self.products.keys() == {"yimecore", "rime-pime"}, "Both products required for complete PE validation"
        return {"count": len(result), "files": result, "arm64_package_claimed": False}

    def run(self):
        self.check("yimecore_manifest_integrity_and_member_paths", lambda: self.package("yimecore"))
        self.check("rime_pime_manifest_integrity_and_member_paths", lambda: self.package("rime-pime"))
        self.check("entrypoints_equal_current_installer_sources", self.installer_sources)
        self.check("core_complete_descriptor_assets_and_fresh_build_binding", self.core)
        self.check("core_clean_source_provenance_bindings", self.core_provenance)
        self.check("rime_required_payload_fresh_build_and_locked_runtime", self.rime)
        self.check("independent_pe_machine_headers", self.pe_headers)
        self.report["passed"] = not self.report["errors"]
        return self.report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "bundle", "core-build", "rime-build", "output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    output = plain(Path(args.output))
    assert output.parent.is_dir(), "Output parent directory must already exist"
    assert not output.exists(), "Preserve earlier report; choose a new output path"
    audit = Audit(args)
    assert not output.is_relative_to(audit.bundle), "Evidence output must be outside the package"
    result = audit.run()
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    print(json.dumps({"passed": result["passed"], "report": str(output),
                      "products": result["products"], "errors": result["errors"]}, ensure_ascii=True, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
