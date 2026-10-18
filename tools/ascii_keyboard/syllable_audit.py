"""Project formal, shared syllable decomposition into the isolated lab layout."""
import csv
from dataclasses import asdict, replace
from pathlib import Path
from yime.utils.syllable_decomposition_audit import (
    DEFAULT_INVENTORY_PATH, SyllableDecompositionRow,
    build_syllable_decomposition_rows,
)
from tools.ascii_keyboard.layout_chain import REPO_ROOT, load_yinyuan_id_to_layout_key
import json


def export_syllable_decomposition_tsv(output_path: Path, *, inventory_path=DEFAULT_INVENTORY_PATH, repo_root=REPO_ROOT):
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    mapping = load_yinyuan_id_to_layout_key(repo_root)
    rows = build_syllable_decomposition_rows(inventory, repo_root=repo_root)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(SyllableDecompositionRow.__dataclass_fields__), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            projected = replace(row, layout_code="".join(mapping[i] for i in (row.shouyin_id,row.huyin_id,row.zhuyin_id,row.moyin_id)))
            writer.writerow(asdict(projected))
    return len(rows)
