"""Build a strict 1-4 character B-lite dictionary for real librime replay.

The historical B-lite export contains the mandatory capacity tier as well as
the requested pypinyin/Wanxiang additions.  The mandatory tier may contain
phrases longer than four characters, so replaying it directly cannot measure
composition from 1-4 character components.  This tool removes those direct
long entries and also enforces the unified character-tier boundary.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
from collections import defaultdict
from pathlib import Path


SCHEMA_TEXT = """# Rime schema
# encoding: utf-8
schema:
  schema_id: yime_component_learning_trial
  name: "Yime strict component learning trial"
  version: "2026-07-26"
engine:
  processors:
    - ascii_composer
    - recognizer
    - key_binder
    - speller
    - punctuator
    - selector
    - navigator
    - express_editor
  segmentors:
    - ascii_segmentor
    - matcher
    - abc_segmentor
    - punct_segmentor
    - fallback_segmentor
  translators:
    - script_translator
    - punct_translator
speller:
  alphabet: "1234567890-=qwertyuiop[]\\\\asdfghjkl;'zxcvbnm,./JKLUIOM<>NG"
  delimiter: " "
translator:
  dictionary: yime_component_learning_trial
  user_dict: yime_component_learning_trial_user
  enable_user_dict: true
  enable_sentence: true
  sentence_over_completion: true
  enable_completion: true
menu:
  page_size: 5
punctuator:
  import_preset: default
key_binder:
  bindings: []
"""


def _load_allowed_hanzi(database: Path, maximum_tier: int) -> set[str]:
    with sqlite3.connect(database) as connection:
        rows = connection.execute(
            """
            SELECT hanzi
            FROM character_tiers
            WHERE tier_number <= ?
              AND encoded_reading_count > 0
            """,
            (maximum_tier,),
        )
        return {str(row[0]) for row in rows}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_dictionary(
    source: Path,
    output: Path,
    database: Path,
    maximum_tier: int,
    maximum_length: int,
) -> dict[str, object]:
    allowed = _load_allowed_hanzi(database, maximum_tier)
    entries_by_length: dict[int, int] = defaultdict(int)
    texts_by_length: dict[int, set[str]] = defaultdict(set)
    rejected = defaultdict(int)
    output.parent.mkdir(parents=True, exist_ok=True)

    in_data = False
    with source.open("r", encoding="utf-8-sig") as source_stream, output.open(
        "w", encoding="utf-8", newline="\n"
    ) as output_stream:
        for raw_line in source_stream:
            line = raw_line.rstrip("\r\n")
            if not in_data:
                if line.startswith("name:"):
                    output_stream.write("name: yime_component_learning_trial\n")
                else:
                    output_stream.write(line + "\n")
                if line.strip() == "...":
                    in_data = True
                continue

            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                output_stream.write(line + "\n")
                continue
            fields = line.split("\t")
            if len(fields) < 2:
                rejected["malformed"] += 1
                continue
            text = fields[0].strip()
            length = len(text)
            if length < 1 or length > maximum_length:
                rejected["outside_length"] += 1
                continue
            if any(char not in allowed for char in text):
                rejected["outside_tier_or_unencoded"] += 1
                continue
            output_stream.write(line + "\n")
            entries_by_length[length] += 1
            texts_by_length[length].add(text)

    return {
        "schema_version": "yime-component-learning-trial-v1",
        "source_dictionary": str(source.resolve()),
        "source_sha256": _sha256(source),
        "output_dictionary": str(output.resolve()),
        "output_sha256": _sha256(output),
        "character_tier_database": str(database.resolve()),
        "maximum_character_tier": maximum_tier,
        "maximum_component_length": maximum_length,
        "allowed_encoded_hanzi": len(allowed),
        "reading_entries_by_length": {
            str(key): entries_by_length[key] for key in sorted(entries_by_length)
        },
        "distinct_texts_by_length": {
            str(key): len(texts_by_length[key]) for key in sorted(texts_by_length)
        },
        "total_reading_entries": sum(entries_by_length.values()),
        "total_distinct_texts": len(set().union(*texts_by_length.values())),
        "rejected": dict(sorted(rejected.items())),
    }


def prepare_runtime_data(
    template: Path,
    output: Path,
    dictionary: Path,
    *,
    exclude_production_dictionary: bool = False,
) -> None:
    output.mkdir(parents=True, exist_ok=True)
    excluded = {
        "yime_core_trial.dict.yaml",
        "yime_full.dict.yaml",
        "yime_shorthand.dict.yaml",
    }
    if exclude_production_dictionary:
        excluded.add("yime_variable.dict.yaml")
    for source in template.iterdir():
        if source.name in excluded or source.name == "build":
            continue
        target = output / source.name
        if source.is_dir():
            shutil.copytree(source, target, dirs_exist_ok=True)
        else:
            shutil.copy2(source, target)
    shutil.copy2(dictionary, output / "yime_component_learning_trial.dict.yaml")
    (output / "yime_component_learning_trial.schema.yaml").write_text(
        SCHEMA_TEXT,
        encoding="utf-8",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--maximum-tier", type=int, default=5)
    parser.add_argument("--maximum-length", type=int, default=4)
    parser.add_argument("--runtime-template", type=Path)
    parser.add_argument("--runtime-output", type=Path)
    parser.add_argument(
        "--exclude-production-dictionary",
        action="store_true",
        help=(
            "Do not copy yime_variable.dict.yaml into the runtime directory. "
            "Use this only for physical-isolation checks; production-baseline "
            "comparison will be unavailable."
        ),
    )
    args = parser.parse_args()

    manifest = build_dictionary(
        source=args.source,
        output=args.output,
        database=args.database,
        maximum_tier=args.maximum_tier,
        maximum_length=args.maximum_length,
    )
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    if bool(args.runtime_template) != bool(args.runtime_output):
        parser.error("--runtime-template and --runtime-output must be used together")
    if args.runtime_template and args.runtime_output:
        prepare_runtime_data(
            args.runtime_template,
            args.runtime_output,
            args.output,
            exclude_production_dictionary=args.exclude_production_dictionary,
        )
        manifest["runtime_data"] = str(args.runtime_output.resolve())
        args.manifest.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(manifest, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
