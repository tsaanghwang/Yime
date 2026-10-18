import json
import shutil
import sqlite3
from pathlib import Path

from yime.utils.rime_export import (
    convert_runtime_code_to_layout_keys,
    export_pinyin_codes_tsv,
    export_rime_files,
    load_runtime_symbol_to_layout_key,
)


def _write_minimal_mapping_files(repo_root: Path) -> None:
    source_root = Path(__file__).resolve().parents[2]
    for relative in (
        Path("internal_data/key_to_symbol.json"),
        Path("internal_data/manual_key_layout.json"),
        Path("syllable/yinyuan/zaoyin_yinyuan_enhanced.json"),
        Path("syllable/yinyuan/yueyin_yinyuan_enhanced.json"),
    ):
        destination = repo_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_root / relative, destination)


def _create_runtime_db(path: Path, repo_root: Path) -> None:
    symbols = json.loads(
        (repo_root / "internal_data" / "key_to_symbol.json").read_text(encoding="utf-8")
    )
    first_code = symbols["N01"] + symbols["M01"]
    phrase_code = first_code + symbols["M25"]
    conn = sqlite3.connect(path)
    try:
        conn.executescript(
            """
            CREATE TABLE runtime_candidates_materialized (
                entry_type TEXT NOT NULL,
                entry_id TEXT NOT NULL,
                text TEXT NOT NULL,
                pinyin_tone TEXT NOT NULL,
                yime_code TEXT NOT NULL,
                full_yime_code TEXT NOT NULL,
                primary_yime_code TEXT NOT NULL,
                variable_yinyuan_code TEXT NOT NULL,
                input_shorthand_code TEXT NOT NULL,
                sort_weight REAL NOT NULL,
                is_common INTEGER NOT NULL,
                text_length INTEGER NOT NULL,
                updated_at TEXT NOT NULL
            );

            """
        )
        conn.executemany(
            """
            INSERT INTO runtime_candidates_materialized (
                entry_type, entry_id, text, pinyin_tone, yime_code,
                full_yime_code, primary_yime_code, variable_yinyuan_code,
                input_shorthand_code, sort_weight, is_common, text_length, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                ("char", "1", "一", "yi1", first_code, first_code, first_code, first_code, symbols["N01"], 120.4, 1, 1, "2026-06-30"),
                ("phrase", "2", "一二", "yi1 er4", phrase_code, phrase_code, phrase_code, phrase_code, first_code, 80.0, 1, 2, "2026-06-30"),
                ("phrase", "3", "一三", "yi1 san1", phrase_code, phrase_code, phrase_code, phrase_code, first_code, 0.0, 0, 2, "2026-06-30"),
            ],
        )
        conn.commit()
    finally:
        conn.close()


def _create_numeric_pinyin_inventory_db(path: Path, repo_root: Path) -> None:
    inventory = json.loads(
        (
            repo_root
            / "internal_data"
            / "pinyin_source_db"
            / "lexicon_exports"
            / "pinyin_normalized.json"
        ).read_text(encoding="utf-8")
    )
    with sqlite3.connect(path) as conn:
        conn.execute(
            "CREATE TABLE numeric_pinyin_inventory (pinyin_tone TEXT NOT NULL)"
        )
        conn.executemany(
            "INSERT INTO numeric_pinyin_inventory (pinyin_tone) VALUES (?)",
            ((pinyin_tone,) for pinyin_tone in inventory),
        )


def test_load_runtime_symbol_to_layout_key_uses_two_layer_manual_layout(tmp_path: Path) -> None:
    _write_minimal_mapping_files(tmp_path)

    symbol_to_key = load_runtime_symbol_to_layout_key(tmp_path)

    symbols = json.loads(
        (tmp_path / "internal_data" / "key_to_symbol.json").read_text(encoding="utf-8")
    )
    assert symbol_to_key[symbols["N01"]] == "b"
    assert symbol_to_key[symbols["M01"]] == "j"
    assert symbol_to_key[symbols["M25"]] == "M"
    assert convert_runtime_code_to_layout_keys(
        symbols["N01"] + symbols["M01"] + symbols["M25"], symbol_to_key
    ) == "bjM"


def test_load_runtime_symbol_to_layout_key_rejects_altgr_yinyuan_id(tmp_path: Path) -> None:
    _write_minimal_mapping_files(tmp_path)
    layout_path = tmp_path / "internal_data" / "manual_key_layout.json"
    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    m25_entry = next(entry for entry in layout["layers"] if entry.get("yinyuan_id") == "M25")
    m25_entry.update(
        physical_key="j",
        output_layer="altgr",
        display_label="AltGr+J",
    )
    layout_path.write_text(json.dumps(layout, ensure_ascii=False), encoding="utf-8")

    try:
        load_runtime_symbol_to_layout_key(tmp_path)
    except ValueError as exc:
        assert "Yinyuan ID must use base/shift, got altgr: M25" in str(exc)
    else:
        raise AssertionError("AltGr Yinyuan ID assignment should be rejected")


def test_load_runtime_symbol_to_layout_key_rejects_parallel_layout(tmp_path: Path) -> None:
    _write_minimal_mapping_files(tmp_path)
    layout_path = tmp_path / "trial-layout.json"
    layout_path.write_text(json.dumps({"yinyuan_id_to_key": {"N01": "q"}}), encoding="utf-8")
    try:
        load_runtime_symbol_to_layout_key(tmp_path, layout_path)
    except ValueError as exc:
        assert "Independent keyboard-layout sources are locked" in str(exc)
    else:
        raise AssertionError("parallel layout source should be rejected")


def test_repo_layout_matches_windows_yime_two_layer_keys() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    layout = json.loads(
        (repo_root / "internal_data" / "manual_key_layout.json").read_text(encoding="utf-8")
    )
    key_to_symbol = json.loads(
        (repo_root / "internal_data" / "key_to_symbol.json").read_text(encoding="utf-8")
    )
    assigned = {
        entry["yinyuan_id"]: entry
        for entry in layout["layers"]
        if entry.get("yinyuan_id")
    }

    expected = {
        "N01": ("b", "base", "b"),
        "N10": ("q", "base", "q"),
        "M01": ("j", "base", "j"),
        "M25": ("m", "shift", "M"),
        "N23": ("y", "base", "y"),
        "N24": ("=", "base", "="),
    }
    for yinyuan_id, (physical_key, output_layer, display_label) in expected.items():
        entry = assigned[yinyuan_id]
        assert entry["physical_key"] == physical_key
        assert entry["output_layer"] == output_layer
        assert entry["display_label"] == display_label

    assert not any(
        entry.get("yinyuan_id") and entry["output_layer"] == "altgr"
        for entry in layout["layers"]
    )

    symbol_to_key = load_runtime_symbol_to_layout_key(repo_root)
    assert {
        yinyuan_id: symbol_to_key[key_to_symbol[yinyuan_id]]
        for yinyuan_id in expected
    } == {
        yinyuan_id: display_label
        for yinyuan_id, (_, _, display_label) in expected.items()
    }


def test_export_canonical_pinyin_codes_uses_fixed_length_layout_keys(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    output_path = tmp_path / "yime_pinyin_codes.tsv"
    db_path = tmp_path / "runtime.db"
    _create_numeric_pinyin_inventory_db(db_path, repo_root)

    row_count = export_pinyin_codes_tsv(
        output_path,
        db_path=db_path,
        repo_root=repo_root,
    )

    lines = output_path.read_text(encoding="utf-8").splitlines()
    assert row_count > 1600
    assert lines[0] == "pinyin_tone\tfull"
    assert all(len(line.split("\t")[1]) == 4 for line in lines[1:])


def test_explicit_pinyin_inventory_uses_codebook_not_stale_runtime_db(
    tmp_path: Path,
) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    output_path = tmp_path / "yime_pinyin_codes.tsv"
    inventory_path = tmp_path / "materialized_syllable_inventory.tsv"
    inventory_path.write_text(
        "numeric_syllable\tmarked_syllable\n"
        "chui5\tchui\n"
        "dian5\tdian\n",
        encoding="utf-8",
    )
    stale_db = tmp_path / "stale-runtime.db"
    with sqlite3.connect(stale_db) as connection:
        connection.execute(
            "CREATE TABLE numeric_pinyin_inventory (pinyin_tone TEXT)"
        )

    row_count = export_pinyin_codes_tsv(
        output_path,
        db_path=stale_db,
        repo_root=repo_root,
        inventory_path=inventory_path,
    )

    rows = output_path.read_text(encoding="utf-8").splitlines()
    assert row_count == 2
    assert rows[0] == "pinyin_tone\tfull"
    assert rows[1].startswith("chui5\t")
    assert rows[2].startswith("dian5\t")
    assert all(len(row.split("\t")[1]) == 4 for row in rows[1:])


def test_export_rime_files_writes_schema_dict_and_metadata(tmp_path: Path) -> None:
    repo_root = tmp_path / "repo"
    repo_root.mkdir()
    _write_minimal_mapping_files(repo_root)
    db_path = tmp_path / "runtime.db"
    output_dir = tmp_path / "rime"
    _create_runtime_db(db_path, repo_root)

    result = export_rime_files(
        db_path=db_path,
        output_dir=output_dir,
        mode="variable",
        code_form="layout-key",
        schema_id="yime_variable_test",
        repo_root=repo_root,
    )

    assert result.row_count == 3
    assert result.code_count == 2
    dict_text = result.paths.dict_path.read_text(encoding="utf-8")
    schema_text = result.paths.schema_path.read_text(encoding="utf-8")
    metadata = json.loads(result.paths.metadata_path.read_text(encoding="utf-8"))

    assert "name: yime_variable_test" in dict_text
    assert "一\tbj\t120" in dict_text
    assert "一二\tbjM\t80" in dict_text
    assert "一三\tbjM\t0" in dict_text
    assert "schema_id: yime_variable_test" in schema_text
    assert 'dictionary: yime_variable_test' in schema_text
    assert "user_dict: yime_variable_test_layout_58f69f370aea" in schema_text
    assert metadata["mode"] == "variable"
    assert metadata["code_form"] == "layout-key"
    assert metadata["row_count"] == 3
    assert metadata["layout_projection_sha256"].startswith("58f69f370aea")
    assert metadata["user_dict_name"] == "yime_variable_test_layout_58f69f370aea"
