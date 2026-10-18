"""Rebuild reviewed erhua inputs for the isolated keyboard lab, never production.

The existing Go compiler owns semantic rewrites and three-mode derivation. This
adapter only supplies a generated layout projection and merges disposable lab
dictionaries. No pronunciation or candidate is inferred from an old dictionary.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def prepare_inputs(repo_root: Path, output: Path) -> Path:
    from yime.canonical_yime_mapping import load_canonical_code_map
    from yime.utils.syllable_decomposition_audit import export_syllable_decomposition_tsv
    from yime.utils.yinyuan_id_chain import (
        load_erhua_key_class_to_layout_key, load_symbol_to_yinyuan_id,
        load_yinyuan_id_to_layout_key,
    )

    output.mkdir(parents=True, exist_ok=True)
    mapping = load_yinyuan_id_to_layout_key(repo_root)
    symbols = load_symbol_to_yinyuan_id(repo_root)
    # This is a disposable projection, not an edit of canonical pinyin codes.
    with (output / "yime_pinyin_codes.tsv").open("w", encoding="utf-8", newline="\n") as stream:
        stream.write("pinyin_tone\tfull\n")
        for pinyin, code in sorted(load_canonical_code_map(repo_root).items()):
            stream.write(pinyin + "\t" + "".join(mapping[symbols[c]] for c in code) + "\n")
    export_syllable_decomposition_tsv(output / "yime_syllable_decomposition.tsv")
    shutil.copyfile(repo_root / "go-backend/input_methods/yime/data/yime_yinyuan_layout.json",
                    output / "yime_yinyuan_layout.json")
    source = repo_root / "docs/project/connected_speech/erhua_sound_key_projection.json"
    projection = json.loads(source.read_text(encoding="utf-8"))
    classes = load_erhua_key_class_to_layout_key(repo_root)
    if set(classes) != {item["key_class_id"] for item in projection["key_classes"]}:
        raise ValueError("Erhua key classes differ from the reviewed semantic inventory")
    for item in projection["key_classes"]:
        if item.get("carrier_yinyuan_id"):
            if classes[item["key_class_id"]] != mapping[item["carrier_yinyuan_id"]]:
                raise ValueError("Shared erhua carrier no longer agrees with base ID")
        else:
            item["layout_key"] = classes[item["key_class_id"]]
            item["purpose"] = "Generated experimental carrier from manual_key_layout.json"
    projection["generated_from"] = [source.relative_to(repo_root).as_posix(),
                                     "internal_data/manual_key_layout.json"]
    path = output / "erhua_sound_key_projection.json"
    path.write_text(json.dumps(projection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def dictionary_rows(path: Path):
    """Yield data only, including symbols such as # in the code column."""
    with path.open(encoding="utf-8-sig") as stream:
        started = False
        for line in stream:
            if not started:
                started = line.strip() == "..."
                continue
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\r\n").split("\t")
            if len(parts) < 3:
                raise ValueError(f"Invalid dictionary row in {path}")
            # Core dictionaries retain syllable separators; table overlays do
            # not. The lab index consumes continuous codes, so compare the same
            # normalized key to avoid duplicate suffix paths and missed buckets.
            yield parts[0], "".join(parts[1].split()), parts[2]


def preserve_base_manifest(data: Path, output: Path) -> dict:
    """Move verified base-only evidence out of the final dictionary directory."""
    source = data / "yime_lexicon_manifest.json"
    manifest = json.loads(source.read_text(encoding="utf-8"))
    expected_names = {f"yime_{mode}.dict.yaml" for mode in ("full", "variable", "shorthand")}
    if set(manifest.get("output_sha256", {})) != expected_names:
        raise ValueError("Base manifest must identify all three dictionaries")
    for name, expected in manifest["output_sha256"].items():
        with (data / name).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != expected:
            raise ValueError(f"Base dictionary identity mismatch: {name}")
    target = output / "base_yime_lexicon_manifest.json"
    source.replace(target)
    return {"path": target.name, "scope": "canonical_base_before_reviewed_overlays",
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest()}


def merge_overlay(core: Path, overlays: list[Path]) -> dict:
    """Preserve core rows/weights; audit exact duplicates and competing buckets."""
    pending = {}
    for path in overlays:
        for text, code, weight in dictionary_rows(path):
            if int(weight) != 1:
                raise ValueError("Reviewed overlays must retain fixed low weight 1")
            pending[text, code] = weight
    proposed = len(pending)
    overlay_codes = {code for _, code in pending}
    core_collisions: dict[str, set[str]] = {}
    existing = 0
    for text, code, _ in dictionary_rows(core):
        if code in overlay_codes:
            core_collisions.setdefault(code, set()).add(text)
        if (text, code) in pending:
            existing += 1
            del pending[text, code]
    by_code: dict[str, list[str]] = {}
    for text, code in pending:
        by_code.setdefault(code, []).append(text)
    with core.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write("# Reviewed PSC and explicit erhua overlays; experiment only.\n")
        for (text, code), weight in sorted(pending.items()):
            stream.write(f"{text}\t{code}\t{weight}\n")
    return {"proposed_pairs": proposed, "already_in_core": existing,
            "appended_pairs": len(pending),
            "core_collision_buckets": {code: sorted(texts) for code, texts in sorted(core_collisions.items())
                                       if code in by_code},
            "overlay_collision_buckets": {code: texts for code, texts in sorted(by_code.items()) if len(texts) > 1}}


def build_reviewed_overlays(repo_root: Path, data: Path, output: Path) -> dict:
    base_manifest = preserve_base_manifest(data, output)
    projection = prepare_inputs(repo_root, data)
    source_dir = repo_root / "docs/project/connected_speech"
    def run(command, *args):
        subprocess.run(["go", "run", command, *map(str, args)],
                       cwd=repo_root / "go-backend", check=True)

    run("./cmd/yime-psc-peripheral-derive", "-repo-root", repo_root,
        "-catalog", source_dir / "psc_pronunciation_peripheral_source.json",
        "-codes", data / "yime_pinyin_codes.tsv", "-data-dir", data,
        "-source-output", output / "psc_source_snapshot.json", "-output-dir", data)
    run("./cmd/yime-erhua-mixed-derive", "-repo-root", repo_root,
        "-data-dir", data, "-sound-projection", projection,
        "-layout", data / "yime_yinyuan_layout.json", "-output-dir", data)
    manifest = json.loads((data / "yime_erhua_mixed_manifest.json").read_text(encoding="utf-8"))
    if not manifest["summary"]["passed"]:
        raise ValueError("Reviewed erhua projection gates did not pass")
    audit = {mode: merge_overlay(data / f"yime_{mode}.dict.yaml", [
        data / f"yime_psc_peripheral_{mode}.dict.yaml",
        data / f"yime_erhua_mixed_{mode}.dict.yaml",
    ]) for mode in ("full", "variable", "shorthand")}
    result = {"scope": "reviewed_explicit_erhua_and_psc_only", "base_manifest": base_manifest,
              "erhua_summary": manifest["summary"], "mode_merge_audit": audit}
    (output / "overlay_audit.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result
