#!/usr/bin/env python3
"""Read-only PR57 release-byte/provenance review; write one new JSON report.

No downloaded code is imported or executed. No package extraction, build, product
process, registry, user profile, or installed product access is performed. Git
is used only to read objects/ancestry. CI status is checked from saved API replies.
Historical build/test assertions are retained as historical evidence, not rerun.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import stat
import struct
import subprocess
import sys
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

SOURCE = "c52168611bbf62653d21357f15c52d230c5588c4"
DELIVERY = "c178f9cf9cab90922fd552081a761d3092138f6b"
MAIN = "d8776121ce90456c2cb8bda6e51b0795364392bd"
MERGE = "76376080df7e58c1fde9f8bb3275f51ddabf20b7"
TAG = "test-simple-pr57-c5216861"
PACKAGE = "Yime-Dual-Product-PR57-20260916.zip"
EVIDENCE = "Yime-PR57-Build-Evidence-20260916.zip"
HISTORY = "docs/testing/simple-maintenance/2026-09-16/pr57-package"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(data):
    return json.loads(data.decode("utf-8-sig"))


def plain(path):
    path = Path(path)
    require(".." not in path.parts, f"Parent traversal rejected: {path}")
    path = path.absolute()
    for part in (path, *path.parents):
        if part.exists() or part.is_symlink():
            info = part.lstat()
            require(not part.is_symlink() and not getattr(info, "st_file_attributes", 0) & 0x400,
                    f"Linked/reparse path rejected: {part}")
    return path


def relative(name):
    require(isinstance(name, str) and bool(name), "Empty/non-string member")
    require(not PurePosixPath(name).is_absolute() and "\\" not in name and ":" not in name,
            f"Non-canonical member: {name!r}")
    for part in name.split("/"):
        require(part not in ("", ".", "..") and not part.endswith((" ", ".")), f"Unsafe member: {name!r}")
        require(not re.match(r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)", part, re.I), f"Device name: {name!r}")
        require(not any(ord(c) < 32 or c in '<>"|?*' for c in part), f"Invalid member: {name!r}")
    return name


def rows_by_path(rows, key="path"):
    result = {}
    folded = set()
    for row in rows:
        name = relative(row[key])
        require(name.casefold() not in folded, f"Duplicate/case-aliased member: {name}")
        folded.add(name.casefold())
        result[name] = row
    return result


def check_bytes(data, row, label):
    require(type(row["bytes"]) is int and row["bytes"] >= 0, f"Invalid size: {label}")
    require(re.fullmatch(r"[0-9a-f]{64}", row["sha256"]) is not None, f"Invalid digest: {label}")
    require(len(data) == row["bytes"] and sha(data) == row["sha256"], f"Size/SHA256 mismatch: {label}")


def git_relation(data, expected_sha, expected_size=None):
    """Allow only exact Git bytes or an explicit LF-to-CRLF text checkout."""
    if sha(data) == expected_sha and (expected_size is None or len(data) == expected_size):
        return "exact_git_bytes"
    if b"\0" not in data:
        converted = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        if sha(converted) == expected_sha and (expected_size is None or len(converted) == expected_size):
            return "git_text_with_crlf_checkout"
    raise ValueError("Bytes differ from source Git object, including explicit CRLF checkout")


class GitObjects:
    def __init__(self, repo):
        self.repo = repo
        self.proc = subprocess.Popen(["git", "-C", str(repo), "cat-file", "--batch"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def read(self, reference):
        require("\n" not in reference, "Invalid Git object reference")
        self.proc.stdin.write(reference.encode("utf-8") + b"\n")
        self.proc.stdin.flush()
        header = self.proc.stdout.readline().split()
        require(len(header) == 3 and header[1] == b"blob", f"Missing/non-blob Git object: {reference}")
        size = int(header[2])
        data = self.proc.stdout.read(size)
        require(len(data) == size and self.proc.stdout.read(1) == b"\n", "Truncated Git object")
        return data

    def close(self):
        self.proc.stdin.close()
        self.proc.wait()
        self.proc.stdout.close()


class Audit:
    def __init__(self, repo, assets, review):
        self.repo, self.assets, self.review = repo, assets, review
        self.history = repo / HISTORY
        self.git = GitObjects(repo)
        self.zips = []
        self.products = {}
        self.report = {
            "schema_version": "yime-pr57-delivery-readonly-review-v1",
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "source_commit": SOURCE, "historical_delivery_commit": DELIVERY, "main_base_commit": MAIN,
            "scope": "Downloaded release bytes, archived provenance, source Git objects and saved GitHub API replies",
            "product_executables_executed": False, "historical_builds_or_tests_rerun": False,
            "historical_verify_package_py_rerun": False, "authenticode_verified": False,
            "installation_or_registry_modified": False, "product_processes_restarted": False,
            "default_input_method_changed": False, "live_user_data_read_or_modified": False,
            "installed_input_acceptance_claimed": False, "checks": [], "errors": [],
            "inputs": {"repo": str(repo), "assets": str(assets), "review": str(review)},
            "verifier_sha256": sha(plain(Path(__file__)).read_bytes()),
        }

    def command(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args])

    def tree(self, commit, scopes=()):
        result = {}
        for record in self.command("ls-tree", "-r", "-z", commit, "--", *scopes).split(b"\0"):
            if not record:
                continue
            meta, raw_name = record.split(b"\t", 1)
            mode, kind, blob = meta.decode().split()
            name = relative(raw_name.decode("utf-8"))
            require(kind == "blob" and mode in ("100644", "100755"), f"Non-regular Git entry: {name}")
            result[name] = blob
        return result

    def local(self, name):
        return plain(self.review / "raw" / relative(name)).read_bytes()

    def history_bytes(self, name):
        return plain(self.history / relative(name)).read_bytes()

    def read_asset(self, name):
        return plain(self.assets / relative(name)).read_bytes()

    def source_relation(self, name, row, blob=None, candidate=None):
        data = self.git.read(blob or SOURCE + ":" + relative(name))
        try:
            return git_relation(data, row["sha256"], row.get("bytes"))
        except ValueError:
            # Some historical tracked text had mixed LF/CRLF. Accept this only
            # with actual candidate bytes that first match the recorded digest.
            if candidate is None:
                candidate = plain(self.repo / relative(name)).read_bytes()
            require(sha(candidate) == row["sha256"] and ("bytes" not in row or len(candidate) == row["bytes"]),
                    f"Source candidate raw bytes do not match recorded digest: {name}")
            require(b"\0" not in data and b"\0" not in candidate and
                    candidate.replace(b"\r\n", b"\n") == data.replace(b"\r\n", b"\n"),
                    f"Source candidate differs beyond CRLF/LF: {name}")
            return "recorded_raw_bytes_verified_crlf_lf_only"

    def check(self, name, action):
        try:
            detail = action()
            self.report["checks"].append({"name": name, "passed": True, "detail": detail})
        except Exception as exc:
            self.report["checks"].append({"name": name, "passed": False})
            self.report["errors"].append({"check": name, "type": type(exc).__name__, "error": str(exc)})

    def release_assets(self):
        fresh = json_bytes(self.local("release.json"))
        receipt = json_bytes(self.read_asset("release-publication.json"))
        require(self.read_asset("release-publication.json") == self.local("release-publication.json"),
                "Saved publication receipt differs from downloaded bytes")
        metadata = json_bytes(self.read_asset("release-artifacts.json"))
        historical = json_bytes(self.history_bytes("raw/github-release-assets.json"))
        require(fresh["id"] == receipt["release_id"] == historical["release_id"] == 389780039, "Release identity differs")
        require(fresh["tag_name"] == metadata["release_tag"] == receipt["tag"] == TAG, "Release tag differs")
        require(fresh["target_commitish"] == metadata["source_commit"] == receipt["tag_commit"] == SOURCE, "Release source differs")
        require(fresh["draft"] is False and fresh["prerelease"] is True, "Release is not published prerelease")
        require(fresh["published_at"] == receipt["published_at"] and receipt["draft"] is False, "Publication state differs")
        require(receipt["prerelease"] is True and receipt["original_uploaded_assets_unchanged"] is True, "Receipt state differs")
        expected = {PACKAGE, EVIDENCE, "SHA256SUMS.txt", "release-artifacts.json", "release-publication.json"}
        current = {row["name"]: row for row in fresh["assets"]}
        require(len(current) == len(fresh["assets"]) and set(current) == expected, "Unexpected release asset set")
        result = []
        for name, row in sorted(current.items()):
            path = plain(self.assets / relative(name))
            with path.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            require(path.stat().st_size == row["size"] and "sha256:" + digest == row["digest"], f"Downloaded asset differs: {name}")
            require(row["state"] == "uploaded", f"Asset incomplete: {name}")
            require(row["browser_download_url"].endswith(f"/{TAG}/{name}"), f"Asset URL differs: {name}")
            result.append({"name": name, "id": row["id"], "bytes": row["size"], "sha256": digest,
                           "download_url": row["browser_download_url"]})
        for old_set in (historical["assets"], receipt["assets"]):
            require({r["name"] for r in old_set} == expected - {"release-publication.json"}, "Original asset set differs")
            for old in old_set:
                now = current[old["name"]]
                require(all(old[k] == now[k] for k in ("id", "size", "digest", "state")), f"Original asset changed: {old['name']}")
        require(self.read_asset("release-artifacts.json") == self.history_bytes("release-artifacts.json"), "Release metadata differs from history")
        require(self.read_asset("SHA256SUMS.txt") == self.history_bytes("SHA256SUMS.txt"), "Checksum file differs from history")
        sums = {}
        for line in self.read_asset("SHA256SUMS.txt").decode("utf-8").splitlines():
            digest, name = line.split()
            require(name not in sums, "Duplicate checksum entry")
            sums[name] = digest
        require(set(sums) == {PACKAGE, EVIDENCE}, "Checksum member set differs")
        require(len(metadata["assets"]) == 2 and {r["name"] for r in metadata["assets"]} == set(sums),
                "Historical package metadata member set differs")
        for row in metadata["assets"]:
            now = current[row["name"]]
            require(row["bytes"] == now["size"] and row["sha256"] == sums[row["name"]] == now["digest"][7:], "Metadata checksum differs")
        return {"release_id": fresh["id"], "published_at": fresh["published_at"], "assets": result,
                "release_publication_receipt_has_no_self_digest": True}

    def provenance_commits(self):
        tag = json_bytes(self.local("tag-ref.json"))
        require(tag["ref"] == "refs/tags/" + TAG and tag["object"] == {
            "sha": SOURCE, "type": "commit",
            "url": f"https://api.github.com/repos/tsaanghwang/Yime/git/commits/{SOURCE}"}, "Tag points elsewhere")
        pr = json_bytes(self.local("pr57.json"))
        require(pr["number"] == 57 and pr["state"] == "MERGED" and pr["mergeCommit"]["oid"] == MERGE, "PR57 merge differs")
        for ancestor, descendant in ((MERGE, SOURCE), (SOURCE, DELIVERY), (SOURCE, MAIN)):
            self.command("merge-base", "--is-ancestor", ancestor, descendant)
        require(self.command("rev-parse", TAG).decode().strip() == SOURCE, "Local tag differs")
        ci_result = []
        for filename, commit, run in (("source-ci.json", SOURCE, 35052224041),
                                      ("delivery-ci.json", DELIVERY, 35079492080),
                                      ("main-ci.json", MAIN, 35294563072)):
            data = json_bytes(self.local(filename))
            if isinstance(data, list):
                require(len(data) == 1, "Ambiguous main CI snapshot")
                data = data[0]
            require(data["headSha"] == commit and data["databaseId"] == run and data["status"] == "completed"
                    and data["conclusion"] == "success", f"CI differs: {filename}")
            for job in data.get("jobs", []):
                require(job["status"] == "completed" and job["conclusion"] == "success", f"CI job not successful: {job['name']}")
            ci_result.append({"headSha": commit, "run": run, "url": data["url"], "successful_jobs_in_snapshot": len(data.get("jobs", []))})
        receipt = json_bytes(self.read_asset("release-publication.json"))
        require(receipt["delivery_commit"] == DELIVERY and receipt["delivery_ci"]["headSha"] == DELIVERY
                and receipt["delivery_ci"]["databaseId"] == 35079492080, "Receipt delivery CI binding differs")
        changes = self.command("diff", "--name-only", SOURCE, MAIN).decode().splitlines()
        return {"source_contains_pr57": True, "source_is_ancestor_of_current_main": True,
                "source_is_ancestor_of_delivery_commit": True, "ci": ci_result,
                "changed_paths_source_to_main": changes, "package_relabelled_as_main": False}

    def check_zip(self, archive, label, count):
        info = archive.infolist()
        names = rows_by_path([{"path": x.filename} for x in info])
        require(len(info) == count, f"ZIP count differs: {label}")
        for row in info:
            require(not row.is_dir() and not row.flag_bits & 1, f"Directory/encrypted member: {row.filename}")
            mode = row.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG), f"Non-regular ZIP member: {row.filename}")
            for parent in PurePosixPath(row.filename).parents:
                if str(parent) != ".":
                    require(str(parent).casefold() not in {n.casefold() for n in names}, f"File/directory alias: {row.filename}")
        require(archive.testzip() is None, f"CRC failure: {label}")
        return {"members": len(names), "uncompressed_bytes": sum(i.file_size for i in info), "crc_passed": True,
                "safe_regular_member_paths": True, "extracted": False}

    def archives(self):
        self.bundle = zipfile.ZipFile(plain(self.assets / PACKAGE))
        self.evidence = zipfile.ZipFile(plain(self.assets / EVIDENCE))
        self.zips.extend((self.bundle, self.evidence))
        return {PACKAGE: self.check_zip(self.bundle, PACKAGE, 238), EVIDENCE: self.check_zip(self.evidence, EVIDENCE, 69)}

    def historical_evidence(self):
        tracked = self.tree(DELIVERY, [HISTORY])
        git_modes = Counter()
        for name, blob in tracked.items():
            data = plain(self.repo / name).read_bytes()
            git_modes[git_relation(self.git.read(blob), sha(data), len(data))] += 1
        historical = rows_by_path(json_bytes(self.history_bytes("evidence-index.json")))
        require(len(historical) == 29, "Historical evidence index count differs")
        for name, row in historical.items():
            check_bytes(self.history_bytes(name), row, name)
            if name == "raw/github-release-assets.json":
                continue  # Created after ZIP publication, present in the Git index.
            base = name.removeprefix("raw/")
            zipped = "core/summary.json" if base == "core-build-summary.json" else (
                "validation/" + base if base.startswith("Test-") or base == "source-validations.json" else base)
            require(self.history_bytes(name) == self.evidence.read(zipped), f"History/archive evidence differs: {name}")
        for name in ("BUILD-PROVENANCE.json", "verify_package.py"):
            require(self.history_bytes(name) == self.evidence.read(name), f"Historical evidence differs: {name}")
        index = rows_by_path(json_bytes(self.evidence.read("evidence-index.json")))
        require(set(index) == set(self.evidence.namelist()) - {"evidence-index.json"}, "Evidence archive index set differs")
        for name, row in index.items():
            check_bytes(self.evidence.read(name), row, name)
        report_bytes = self.evidence.read("independent-package-verification.json")
        self.provenance = json_bytes(self.evidence.read("BUILD-PROVENANCE.json"))
        p = self.provenance
        metadata = json_bytes(self.read_asset("release-artifacts.json"))
        require(p["source_commit"] == p["installer_source_commit"] == SOURCE, "Build provenance source differs")
        require(p["independent_verification_sha256"] == metadata["independent_verification_sha256"] == sha(report_bytes), "Historical report binding differs")
        require(metadata["build_provenance_sha256"] == sha(self.evidence.read("BUILD-PROVENANCE.json")), "Build provenance checksum differs")
        old = json_bytes(report_bytes)
        expected = {"yimecore_manifest_integrity_and_member_paths", "rime_pime_manifest_integrity_and_member_paths",
                    "entrypoints_equal_current_installer_sources", "core_complete_descriptor_assets_and_fresh_build_binding",
                    "core_clean_source_provenance_bindings", "rime_required_payload_fresh_build_and_locked_runtime", "independent_pe_machine_headers"}
        require(old["passed"] is True and not old["errors"] and len(old["checks"]) == 7
                and {c["name"] for c in old["checks"]} == expected and all(c["passed"] is True for c in old["checks"]), "Historical independent checks failed")
        return {"historical_git_files": len(tracked), "historical_git_byte_relations": dict(git_modes), "historical_index_files": len(historical),
                "evidence_zip_index_files": len(index), "historical_independent_checks": 7,
                "independent_report_sha256": sha(report_bytes), "historical_verifier_executed": False}

    def source_records(self):
        source = json_bytes(self.evidence.read("source-inputs.json"))
        require(source["source_commit"] == SOURCE and not source["git_status"] and not source["missing_tracked_files"], "Source input identity/state differs")
        require(sha(self.evidence.read("source-inputs.json")) == self.provenance["source_inputs_sha256"], "Source inputs binding differs")
        tree = self.tree(SOURCE, source["scope"])
        rows = rows_by_path(source["files"])
        require(set(tree) == set(rows), "Source inventory scope differs from Git commit")
        source_modes = Counter()
        for name, row in rows.items():
            require(tree[name] == row["git_blob"], f"Source Git blob differs: {name}")
            try:
                source_modes[self.source_relation(name, row, tree[name])] += 1
            except ValueError as exc:
                raise ValueError(f"Source inventory bytes differ: {name}: {exc}") from exc
        manifest = json_bytes(self.evidence.read("core/build/source-manifest.json"))
        require(manifest["git_commit"] == SOURCE and manifest["dirty"] is False and not manifest["git_status"], "Core source identity/state differs")
        manifest_rows = rows_by_path(manifest["files"])
        overlap = set(rows) & set(manifest_rows)
        require(len(overlap) == 615, "Source inventory overlap count differs")
        for name in overlap:
            require(all(rows[name][key] == manifest_rows[name][key] for key in ("bytes", "sha256")),
                    f"Source inventories disagree: {name}")
        archive = zipfile.ZipFile(io.BytesIO(self.evidence.read("core/source-snapshot.zip")))
        self.zips.append(archive)
        snapshot_result = self.check_zip(archive, "core/source-snapshot.zip", 660)
        require(set(manifest_rows) == set(archive.namelist()), "Core snapshot member set differs")
        full_tree = self.tree(SOURCE)
        core_modes = Counter()
        for name, row in manifest_rows.items():
            check_bytes(archive.read(name), row, "core snapshot/" + name)
            require(name in full_tree, f"Core snapshot source absent from Git: {name}")
            core_modes[self.source_relation(name, row, full_tree[name], archive.read(name))] += 1
        inventory = json_bytes(self.evidence.read("speech/source-hashes-after.json"))
        require(self.evidence.read("speech/source-hashes-before.json") == self.evidence.read("speech/source-hashes-after.json"), "Speech source inventory changed")
        speech_modes = Counter()
        for name, row in rows_by_path(inventory).items():
            require(name in full_tree, f"Speech source absent from Git: {name}")
            speech_modes[self.source_relation(name, row, full_tree[name])] += 1
        forward = json_bytes(self.evidence.read("speech/forward-source.json"))
        require(forward["passed"] is True and len(forward["inputs"]) == 56, "Forward source record differs")
        for row in forward["inputs"]:
            name = relative(row["path"])
            require(forward["input_sha256"][name] == row["sha256"], f"Forward input map differs: {name}")
            self.source_relation(name, row, full_tree[name])
        return {"source_inputs_files": len(rows), "source_input_byte_relations": dict(source_modes),
                "core_snapshot": snapshot_result, "core_source_byte_relations": dict(core_modes),
                "matching_source_inventory_overlap": len(overlap),
                "speech_source_files": len(inventory), "speech_source_byte_relations": dict(speech_modes),
                "speech_forward_inputs": len(forward["inputs"]), "all_records_bound_to_exact_source_commit": SOURCE,
                "line_ending_policy": "Exact Git blob; explicit CRLF checkout; or actual raw bytes matching recorded SHA256/size with only CRLF/LF differences"}

    def packages(self):
        results = {}
        for product, expected_count in (("yimecore", 65), ("rime-pime", 160)):
            data = self.bundle.read(product + "/product-package.json")
            manifest = json_bytes(data)
            require(data == self.evidence.read(product + "-product-package.json"), f"Evidence manifest differs: {product}")
            require(manifest["format"] == "yime-simple-package-1" and manifest["product"] == product, "Package format/identity differs")
            rows = rows_by_path(manifest["files"])
            require(len(rows) == expected_count, f"Payload count differs: {product}")
            prefix = product + "/payload/"
            actual = {name[len(prefix):] for name in self.bundle.namelist() if name.startswith(prefix)}
            require(actual == set(rows), f"Unlisted/missing payload: {product}")
            for name, row in rows.items():
                check_bytes(self.bundle.read(prefix + name), row, product + "/" + name)
            result = {"version": manifest["version"], "manifest_sha256": sha(data), "file_count": len(rows),
                      "total_bytes": sum(r["bytes"] for r in rows.values())}
            old = self.provenance["products"][product]
            require(all(old[key] == value for key, value in result.items()), f"Provenance package summary differs: {product}")
            self.products[product] = rows
            results[product] = result
        expected_top = {"Install-Uninstall.cmd", "Manage-Products.ps1", "Choose-Products.ps1", "DELIVERY-README.md", "BUILD-PROVENANCE.json"}
        for product, rows in self.products.items():
            expected_top.update(product + "/" + n for n in ("Setup.ps1", "Setup.cmd", "Product.psm1", "product-package.json"))
            expected_top.update(product + "/payload/" + n for n in rows)
        require(set(self.bundle.namelist()) == expected_top, "Unexpected bundle files")
        require(self.bundle.read("BUILD-PROVENANCE.json") == self.evidence.read("BUILD-PROVENANCE.json"), "Bundled provenance differs")
        # The Git note was finalized after ZIP hashes existed. The packaging-time
        # copy is bound by the full archive digest and need not equal that note.
        note = self.bundle.read("DELIVERY-README.md")
        return {"products": results, "bundled_development_note": {
            "member": "DELIVERY-README.md", "bytes": len(note), "sha256": sha(note),
            "equals_later_historical_git_note": note == self.history_bytes("DEVELOPMENT.md"),
            "binding": "Packaging-time text bound by the verified release archive digest"}}

    def installer_sources(self):
        names = {n: n for n in ("Install-Uninstall.cmd", "Manage-Products.ps1", "Choose-Products.ps1")}
        names.update({p + "/" + n: n for p in ("yimecore", "rime-pime") for n in ("Setup.ps1", "Setup.cmd", "Product.psm1")})
        results = []
        for member, filename in names.items():
            path = "installer/simple/" + filename
            data = self.bundle.read(member)
            source = self.git.read(SOURCE + ":" + path)
            require(source == self.git.read(MAIN + ":" + path), f"Installer source changed on main: {path}")
            mode = self.source_relation(path, {"sha256": sha(data), "bytes": len(data)}, candidate=data)
            worktree = plain(self.repo / path).read_bytes()
            require(worktree == data, f"Installed entrypoint differs from current worktree bytes: {member}")
            results.append({"member": member, "sha256": sha(data), "bytes": len(data), "source_git_relation": mode,
                            "main_git_blob_unchanged": True, "current_worktree_bytes_identical": True})
        return {"count": len(results), "files": results}

    def required_resources(self):
        core = self.products["yimecore"]
        descriptor_data = self.bundle.read("yimecore/payload/local-product.json")
        git_relation(self.git.read(SOURCE + ":tools/yimecore/local-product.json"), sha(descriptor_data), len(descriptor_data))
        descriptor = json_bytes(descriptor_data)
        require(descriptor["identity"]["clsid"] == "{E40FA752-BB96-461D-A51D-F40EB437EC65}" and
                descriptor["identity"]["profile"] == "{126F54C6-E9B1-4E22-8652-03224CBD49F9}", "Core identity is not current product")
        require(descriptor["scope"]["active_architectures"] == ["x64", "x86"], "Unexpected architecture scope")
        required = {b["path"] for b in descriptor["go_binaries"]}
        required.update(f"{arch}/{name}" for arch in ("x64", "x86") for name in descriptor["native_binaries"])
        required.update(a["path"] for a in descriptor["assets"])
        required.update(f"indexes/{m}.yidx" for m in ("full", "variable", "shorthand"))
        speech = {"speech-capability.json", "speech/product.json", "speech/admission.json", "speech/forward-source.json", "speech/admitted-records.json"}
        speech.update(f"speech/indexes/{m}-{k}.yidx" for m in ("full", "variable", "shorthand") for k in ("core", "stage5c"))
        required.update(speech | {"local-product.json"})
        require(required == set(core), "Core descriptor-derived complete payload differs")
        for asset in descriptor["assets"]:
            self.source_relation(asset["source"], core[asset["path"]],
                                 candidate=self.bundle.read("yimecore/payload/" + asset["path"]))
        old = json_bytes(self.evidence.read("independent-package-verification.json"))
        old_rime = next(c["detail"] for c in old["checks"] if c["name"] == "rime_required_payload_fresh_build_and_locked_runtime")
        rime = self.products["rime-pime"]
        require(set(old_rime["required_files"]).issubset(rime), "Historically required Rime resources absent")
        base = "go-backend/input_methods/yime/"
        required_rime = {"PIMELauncher.exe", "backends.json", "go-backend/server.exe", base + "ime.json", base + "data/fonts/YinYuan-Regular.ttf"}
        required_rime.update(f"{arch}/{name}" for arch in ("x64", "x86") for name in ("PIMETextService.dll", "PIMERegistrationStatus.exe"))
        require(required_rime.issubset(rime), "Independent Rime resources absent")
        lock_data = self.bundle.read("rime-pime/payload/" + base + "rime_runtime.lock.json")
        git_relation(self.git.read(SOURCE + ":" + base + "rime_runtime.lock.json"), sha(lock_data), len(lock_data))
        lock = json_bytes(lock_data)
        require(lock["platform"] == "Windows-msvc-x64" and set(lock["files"]) == {"rime.dll", "rime_deployer.exe", "rime_dict_manager.exe"}, "Runtime lock differs")
        require(sha(lock_data) == self.provenance["rime"]["runtime_lock_sha256"], "Rime lock provenance differs")
        for filename, digest in lock["files"].items():
            require(rime[base + filename]["sha256"] == digest.lower(), "Pinned Rime runtime digest differs")
        source_assets = 0
        for name, row in rime.items():
            require(not (name.endswith(".go") or "/brise/" in name or "yime_core_trial." in name or name.endswith(".bak-32bit")), f"Retired/source Rime payload: {name}")
            if name.startswith(base):
                self.source_relation(name, row, candidate=self.bundle.read("rime-pime/payload/" + name))
                source_assets += 1
        return {"core_complete_required_files": len(required), "core_source_assets": len(descriptor["assets"]),
                "core_speech_payloads": len(speech), "rime_historical_required_files": len(old_rime["required_files"]),
                "rime_source_assets_bound_to_source_commit": source_assets, "locked_runtime_files": len(lock["files"])}

    def build_bindings(self):
        inputs = json_bytes(self.evidence.read("core/build/build-inputs.json"))
        p = self.provenance
        for key, member in (("source_manifest_sha256", "core/build/source-manifest.json"),
                            ("source_archive_sha256", "core/source-snapshot.zip")):
            require(sha(self.evidence.read(member)) == inputs[key] == p["core"][key], "Core source binding differs: " + key)
        require(sha(self.evidence.read("core/build/build-inputs.json")) == p["core"]["build_inputs_sha256"], "Core build inputs binding differs")
        require(inputs["installed_package_used_as_input"] is False and inputs["indexes_rebuilt_byte_identical"] is True, "Historical build scope differs")
        core = self.products["yimecore"]
        require(len(inputs["index_builds"]) == 3 and {r["build"]["mode"] for r in inputs["index_builds"]} == {"full", "variable", "shorthand"}, "Index build modes differ")
        for row in inputs["index_builds"]:
            b = row["build"]
            require(row["verified"] is True, "Historical index check failed")
            require(core[f"indexes/{b['mode']}.yidx"]["sha256"] == b["index_sha256"] and
                    core[f"indexes/{b['mode']}.yidx"]["bytes"] == b["index_bytes"], "Index build binding differs")
            require(core[f"data/yime_{b['mode']}.dict.yaml"]["sha256"] == b["source_sha256"] and
                    core[f"data/yime_{b['mode']}.dict.yaml"]["bytes"] == b["source_bytes"], "Index source binding differs")
        speech = inputs["speech"]
        require(speech == p["core"]["speech_binding"], "Speech build/provenance binding differs")
        for key, member in (("admission_summary_sha256", "speech/summary.json"),
                            ("source_inventory_sha256", "speech/source-hashes-after.json"),
                            ("export_receipt_sha256", "core/speech-product-export-mapping.json")):
            require(sha(self.evidence.read(member)) == speech[key], "Speech archived binding differs: " + key)
        require(core["speech-capability.json"]["sha256"] == speech["capability_sha256"] and
                core["speech/product.json"]["sha256"] == speech["product_manifest_sha256"], "Speech product binding differs")
        receipt = json_bytes(self.evidence.read("core/speech-product-export-mapping.json"))
        require(receipt["passed"] is True and receipt["inputs_unchanged"] is True and receipt["product_verified"] is True, "Speech export receipt failed")
        require(len(receipt["files"]) == receipt["payload_files"] == 11, "Speech payload count differs")
        for row in receipt["files"]:
            check_bytes(self.bundle.read("yimecore/payload/" + relative(row["product_path"])), row, row["product_path"])
        for key in ("admission_summary", "source_inventory", "source_inventory_before"):
            row = receipt[key]
            check_bytes(self.evidence.read("speech/" + relative(row["path"])), row, row["path"])
        require(self.bundle.read("yimecore/payload/speech/forward-source.json") == self.evidence.read("speech/forward-source.json"), "Speech forward-source bytes differ")
        summary = json_bytes(self.evidence.read("core/summary.json"))
        require(summary["passed"] is True and summary["registration_and_default_preserved"] is True, "Historical core summary failed")
        return {"source_commit": SOURCE, "normal_index_bindings": 3, "speech_payload_bindings": 11,
                "source_manifest_sha256": inputs["source_manifest_sha256"], "source_archive_sha256": inputs["source_archive_sha256"],
                "build_inputs_sha256": p["core"]["build_inputs_sha256"],
                "historical_build_success_and_index_rebuild_claims_rehashed_not_rerun": True}

    def pe_headers(self):
        result = []
        for product, rows in self.products.items():
            for name in sorted(rows):
                if Path(name).suffix.lower() not in (".exe", ".dll"):
                    continue
                data = self.bundle.read(product + "/payload/" + name)
                require(len(data) >= 64 and data[:2] == b"MZ", f"Invalid DOS header: {name}")
                offset = struct.unpack_from("<I", data, 0x3C)[0]
                require(64 <= offset <= len(data) - 24 and data[offset:offset + 4] == b"PE\0\0", f"Invalid PE header: {name}")
                machine = struct.unpack_from("<H", data, offset + 4)[0]
                expected = 0x14C if name.startswith("x86/") or (product == "rime-pime" and name == "PIMELauncher.exe") else 0x8664
                require(machine == expected, f"Wrong PE architecture: {product}/{name}")
                result.append({"product": product, "path": name, "machine": f"0x{machine:04x}", "architecture": "x86" if machine == 0x14C else "x64"})
        require(len(result) == 45 and set(self.products) == {"yimecore", "rime-pime"}, "PE file count differs")
        return {"count": len(result), "architectures": dict(Counter(r["architecture"] for r in result)), "files": result,
                "authenticode_check_performed": False, "native_execution_performed": False}

    def run(self):
        steps = [("release_assets_and_publication_receipt", self.release_assets),
                 ("source_tag_pr57_ancestry_and_ci", self.provenance_commits),
                 ("release_archives_crc_and_member_safety", self.archives),
                 ("historical_git_evidence_and_independent_report", self.historical_evidence),
                 ("source_inventories_and_snapshot_bound_to_git", self.source_records),
                 ("complete_product_payload_manifest_hashes", self.packages),
                 ("installer_entrypoints_source_main_and_worktree", self.installer_sources),
                 ("independent_required_resources_and_source_assets", self.required_resources),
                 ("core_build_and_speech_provenance_bindings", self.build_bindings),
                 ("independent_pe_architecture_headers", self.pe_headers)]
        try:
            for name, action in steps:
                self.check(name, action)
            self.report["input_api_snapshot_hashes"] = {}
            for name in ("release.json", "tag-ref.json", "pr57.json", "source-ci.json", "delivery-ci.json", "main-ci.json", "release-publication.json"):
                try:
                    self.report["input_api_snapshot_hashes"][name] = sha(self.local(name))
                except Exception as exc:
                    self.report["errors"].append({"check": "input_snapshot_digest", "input": name,
                                                  "type": type(exc).__name__, "error": str(exc)})
            self.report["passed"] = not self.report["errors"]
            return self.report
        finally:
            for archive in self.zips:
                archive.close()
            self.git.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repo", "assets", "output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    repo, assets, output = (plain(v) for v in (args.repo, args.assets, args.output))
    review = plain(Path(__file__).parent)
    require(output.parent.is_dir() and not output.exists(), "Output must be a new file in an existing directory")
    require(output.is_relative_to(review / "raw"), "Output must be in this review's raw directory")
    require(not output.is_relative_to(assets), "Output cannot overwrite asset evidence")
    audit = Audit(repo, assets, review)
    result = audit.run()
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    print(json.dumps({"passed": result["passed"], "checks": len(result["checks"]), "output": str(output), "errors": result["errors"]}, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
