from __future__ import annotations

import json
import os
import re
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "yime" / "pinyin_hanzi.db"
SCHEMA_PATH = ROOT / "yime" / "create_yime_db_schema.sql"
LOCAL_KLC_PATH = ROOT / "yinyuan.klc"
DEFAULT_EXTERNAL_REPO = ROOT.parent / "Yime-keyboard-layout"
EXTERNAL_REPO = Path(
    os.environ.get("YIME_KEYBOARD_LAYOUT_REPO", str(DEFAULT_EXTERNAL_REPO))
).expanduser().resolve()
EXTERNAL_KLC_PATH = EXTERNAL_REPO / "yinyuan.klc"
RUNTIME_SYMBOL_PATH = ROOT / "syllable_codec" / "key_to_code.json"
CANONICAL_SYMBOL_PATH = ROOT / "internal_data" / "key_to_symbol.json"
PROJECTION_PATH = ROOT / "internal_data" / "bmp_pua_trial_projection.json"
SHOUYIN_PATH = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "shouyin_codepoint.json"
YINYUAN_PATH = ROOT / "syllable" / "analysis" / "slice" / "yinyuan" / "yinyuan_codepoint.json"

KLC_ROW_RE = re.compile(
    r"^\s*(?P<scan>[0-9A-Fa-f]+)\s+"
    r"(?P<vk>\S+)\s+"
    r"(?P<cap>\S+)\s+"
    r"(?P<s0>\S+)\s+"
    r"(?P<s1>\S+)\s+"
    r"(?P<s2>\S+)\s+"
    r"(?P<s6>\S+)"
    r"(?:\s*//\s*(?P<comment>.*))?$"
)

VK_TO_KEY_CODE = {
    "1": "1",
    "2": "2",
    "3": "3",
    "4": "4",
    "5": "5",
    "6": "6",
    "7": "7",
    "8": "8",
    "9": "9",
    "0": "0",
    "OEM_MINUS": "-",
    "OEM_PLUS": "=",
    "OEM_4": "[",
    "OEM_6": "]",
    "OEM_5": "\\",
    "OEM_1": ";",
    "OEM_7": "'",
    "OEM_3": "`",
    "OEM_COMMA": ",",
    "OEM_PERIOD": ".",
    "OEM_2": "/",
    "SPACE": "space",
}

def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def format_codepoint(value: str | None) -> str | None:
    if not value:
        return None
    width = 6 if ord(value) > 0xFFFF else 4
    return f"U+{ord(value):0{width}X}"


def build_label_index() -> dict[str, str]:
    labels: dict[str, str] = {}

    shouyin_payload = load_json(SHOUYIN_PATH)
    shouyin_map = shouyin_payload.get("首音", {})
    for label, char in shouyin_map.items():
        labels[str(char)] = str(label)

    yinyuan_payload = load_json(YINYUAN_PATH)
    for namespace in ("zaoyin", "yueyin"):
        namespace_map = yinyuan_payload.get(namespace, {})
        for label, char in namespace_map.items():
            labels[str(char)] = str(label)

    return labels


def slot_sort_key(slot_key: str) -> tuple[int, int]:
    prefix = 0 if slot_key.startswith("N") else 1
    return (prefix, int(slot_key[1:]))


def load_symbol_catalog() -> list[dict[str, object]]:
    runtime_map = load_json(RUNTIME_SYMBOL_PATH)
    canonical_map = load_json(CANONICAL_SYMBOL_PATH)
    projection_payload = load_json(PROJECTION_PATH)
    projection_map = projection_payload.get("used_mapping", {})
    label_index = build_label_index()

    rows: list[dict[str, object]] = []
    slot_keys = sorted(projection_map.keys(), key=slot_sort_key)
    for ordinal, slot_key in enumerate(slot_keys, start=1):
        projection_entry = projection_map.get(slot_key, {})
        bmp_char = runtime_map.get(slot_key) or projection_entry.get("char")
        canonical_char = canonical_map.get(slot_key)
        category = "initial" if slot_key.startswith("N") else "musical"
        label = label_index.get(str(bmp_char or ""), "")

        rows.append(
            {
                "symbol_id": f"sym_{ordinal:03d}",
                "source_symbol_key": slot_key,
                "slot_key": slot_key,
                "slot_number": projection_entry.get("slot"),
                "symbol_category": category,
                "yinyuan_label": label,
                "pua_char": bmp_char,
                "codepoint_hex": projection_entry.get("codepoint") or format_codepoint(bmp_char),
                "canonical_char": canonical_char,
                "canonical_codepoint_hex": format_codepoint(canonical_char),
                "sort_order": projection_entry.get("slot") or ordinal,
                "symbol_name_zh": label or slot_key,
                "notes_zh": f"Imported from slot crosswalk sources; slot={slot_key}",
            }
        )

    return rows


def decode_klc_token(token: str | None) -> str | None:
    if not token or token in {"%%", "-1"}:
        return None
    if len(token) == 1:
        return token
    if re.fullmatch(r"[0-9A-Fa-f]{4,6}", token):
        return chr(int(token, 16))
    return token


def resolve_key_code(vk_name: str) -> str | None:
    if vk_name in VK_TO_KEY_CODE:
        return VK_TO_KEY_CODE[vk_name]
    if len(vk_name) == 1 and vk_name.isalpha():
        return vk_name.lower()
    return None


def resolve_klc_path() -> Path:
    if LOCAL_KLC_PATH.exists():
        return LOCAL_KLC_PATH
    if EXTERNAL_KLC_PATH.exists():
        return EXTERNAL_KLC_PATH
    raise FileNotFoundError(
        "Could not find yinyuan.klc in either the main repo root or the external Yime-keyboard-layout repo. "
        f"Set YIME_KEYBOARD_LAYOUT_REPO if needed. Checked: {LOCAL_KLC_PATH} and {EXTERNAL_KLC_PATH}"
    )


def parse_klc_layout(klc_path: Path) -> list[dict[str, str | None]]:
    lines = klc_path.read_text(encoding="utf-16").splitlines()
    in_layout = False
    rows: list[dict[str, str | None]] = []

    for line in lines:
        if line.startswith("LAYOUT"):
            in_layout = True
            continue
        if in_layout and line.startswith("LIGATURE"):
            break
        if not in_layout:
            continue
        if not line.strip() or line.lstrip().startswith("//"):
            continue

        match = KLC_ROW_RE.match(line)
        if not match:
            continue

        payload = match.groupdict()
        rows.append(
            {
                "scan_code": payload["scan"],
                "vk_name": payload["vk"],
                "cap_state": payload["cap"],
                "state_0_token": payload["s0"],
                "state_1_token": payload["s1"],
                "state_2_token": payload["s2"],
                "state_6_token": payload["s6"],
                "state_0_char": decode_klc_token(payload["s0"]),
                "state_1_char": decode_klc_token(payload["s1"]),
                "state_2_char": decode_klc_token(payload["s2"]),
                "state_6_char": decode_klc_token(payload["s6"]),
                "comment_text": payload.get("comment") or "",
            }
        )

    return rows


def apply_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))


def import_symbols(conn: sqlite3.Connection, symbols: list[dict[str, object]]) -> None:
    conn.execute("DELETE FROM key_symbol_map")
    conn.execute("DELETE FROM symbol")

    conn.executemany(
        """
        INSERT INTO symbol (
            symbol_id, source_symbol_key, slot_key, slot_number, symbol_category,
            yinyuan_label, pua_char, codepoint_hex, canonical_char,
            canonical_codepoint_hex, sort_order, symbol_name_zh, notes_zh
        ) VALUES (
            :symbol_id, :source_symbol_key, :slot_key, :slot_number, :symbol_category,
            :yinyuan_label, :pua_char, :codepoint_hex, :canonical_char,
            :canonical_codepoint_hex, :sort_order, :symbol_name_zh, :notes_zh
        )
        ON CONFLICT(symbol_id) DO UPDATE SET
            source_symbol_key = excluded.source_symbol_key,
            slot_key = excluded.slot_key,
            slot_number = excluded.slot_number,
            symbol_category = excluded.symbol_category,
            yinyuan_label = excluded.yinyuan_label,
            pua_char = excluded.pua_char,
            codepoint_hex = excluded.codepoint_hex,
            canonical_char = excluded.canonical_char,
            canonical_codepoint_hex = excluded.canonical_codepoint_hex,
            sort_order = excluded.sort_order,
            symbol_name_zh = excluded.symbol_name_zh,
            notes_zh = excluded.notes_zh
        """,
        symbols,
    )
    conn.execute(
        """
        INSERT INTO db_meta (meta_key, meta_value)
        VALUES ('symbol_source_json', ?)
        ON CONFLICT(meta_key) DO UPDATE SET meta_value = excluded.meta_value, updated_at = CURRENT_TIMESTAMP
        """,
        ("slot_crosswalk:key_to_code.json+key_to_symbol.json+bmp_pua_trial_projection.json",),
    )


def rebuild_default_key_mappings(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        INSERT INTO key_symbol_map (mapping_id, key_id, symbol_id, map_layer)
        SELECT
            ROW_NUMBER() OVER (ORDER BY pk.key_id),
            pk.key_id,
            s.symbol_id,
            'default'
        FROM physical_key AS pk
        JOIN symbol AS s
            ON s.source_symbol_key = pk.key_code
        WHERE LENGTH(pk.key_code) = 1
          AND ((pk.key_code BETWEEN 'a' AND 'z') OR (pk.key_code BETWEEN 'A' AND 'Z'))
        """
    )


def import_klc_rows(conn: sqlite3.Connection, klc_path: Path, rows: list[dict[str, str | None]]) -> None:
    conn.execute("DELETE FROM klc_layout_source WHERE source_file = ?", (klc_path.name,))
    conn.execute("DELETE FROM key_symbol_map WHERE map_layer IN ('klc_base', 'klc_shift', 'klc_ctrl', 'klc_ctrl_alt')")

    insert_rows = [
        (
            row["scan_code"],
            row["vk_name"],
            row["cap_state"],
            row["state_0_token"],
            row["state_1_token"],
            row["state_2_token"],
            row["state_6_token"],
            row["state_0_char"],
            row["state_1_char"],
            row["state_2_char"],
            row["state_6_char"],
            row["comment_text"],
            klc_path.name,
        )
        for row in rows
    ]

    conn.executemany(
        """
        INSERT INTO klc_layout_source (
            scan_code, vk_name, cap_state,
            state_0_token, state_1_token, state_2_token, state_6_token,
            state_0_char, state_1_char, state_2_char, state_6_char,
            comment_text, source_file
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        insert_rows,
    )

    conn.execute(
        """
        INSERT INTO db_meta (meta_key, meta_value)
        VALUES ('klc_source_file', ?)
        ON CONFLICT(meta_key) DO UPDATE SET meta_value = excluded.meta_value, updated_at = CURRENT_TIMESTAMP
        """,
        (str(klc_path.relative_to(ROOT)),),
    )


def import_derived_key_mappings(conn: sqlite3.Connection, rows: list[dict[str, str | None]]) -> int:
    reverse_mapping = dict(conn.execute("SELECT pua_char, symbol_id FROM symbol"))
    physical_key_index = dict(conn.execute("SELECT key_code, key_id FROM physical_key"))
    inserted = 0

    for row in rows:
        key_code = resolve_key_code(str(row["vk_name"]))
        if not key_code:
            continue
        key_id = physical_key_index.get(key_code)
        if not key_id:
            continue

        for column, map_layer in (
            ("state_0_char", "klc_base"),
            ("state_1_char", "klc_shift"),
            ("state_2_char", "klc_ctrl"),
            ("state_6_char", "klc_ctrl_alt"),
        ):
            char = row[column]
            symbol_id = reverse_mapping.get(char) if char else None
            if not symbol_id:
                continue

            conn.execute(
                """
                INSERT OR REPLACE INTO key_symbol_map (mapping_id, key_id, symbol_id, map_layer)
                VALUES (
                    COALESCE(
                        (SELECT mapping_id FROM key_symbol_map WHERE key_id = ? AND map_layer = ?),
                        (SELECT IFNULL(MAX(mapping_id), 0) + 1 FROM key_symbol_map)
                    ),
                    ?, ?, ?
                )
                """,
                (key_id, map_layer, key_id, symbol_id, map_layer),
            )
            inserted += 1

    return inserted


def main() -> None:
    symbols = load_symbol_catalog()
    klc_path = resolve_klc_path()
    klc_rows = parse_klc_layout(klc_path)

    with sqlite3.connect(DB_PATH) as conn:
        apply_schema(conn)
        import_symbols(conn, symbols)
        rebuild_default_key_mappings(conn)
        import_klc_rows(conn, klc_path, klc_rows)
        mapping_count = import_derived_key_mappings(conn, klc_rows)
        conn.commit()

        print(f"Imported {len(symbols)} symbols from slot crosswalk sources")
        print(f"Imported {len(klc_rows)} layout rows from {klc_path}")
        print(f"Imported {mapping_count} derived key-symbol mappings from KLC states")


if __name__ == "__main__":
    main()
