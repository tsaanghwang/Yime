from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
KLC_PATH = ROOT / "yinyuan.klc"
LAYOUT_PATH = ROOT / "internal_data" / "manual_key_layout.json"
SYMBOL_PATH = ROOT / "internal_data" / "key_to_symbol.json"
BMP_PROJECTION_PATH = ROOT / "internal_data" / "bmp_pua_trial_projection.json"

HEADER_LINES = [
    'KBD\tYinyuan\t"Chinese (Simplified) - Yinyuan"',
    '',
    'COPYRIGHT\t"(c) 2026 Yime"',
    '',
    'COMPANY\t"Yime"',
    '',
    'LOCALENAME\t"zh-CN"',
    '',
    'LOCALEID\t"00000804"',
    '',
    'VERSION\t1.0',
    '',
    'SHIFTSTATE',
    '',
    '0\t//Column 4',
    '1\t//Column 5 : Shft',
    '2\t//Column 6 :       Ctrl',
    '6\t//Column 7 :       Ctrl Alt',
    '',
    'LAYOUT\t\t;an extra \"@\" at the end is a dead key',
    '',
    '//SC\tVK_\t\t\tCap\t0\t1\t2\t6',
    '//--\t----\t\t\t----\t----\t----\t----\t----',
    '',
]

STANDARD_LAYOUT_TEMPLATE = [
    {"scan": "29", "vk": "OEM_3", "cap": "0"},
    {"scan": "02", "vk": "1", "cap": "0"},
    {"scan": "03", "vk": "2", "cap": "0"},
    {"scan": "04", "vk": "3", "cap": "0"},
    {"scan": "05", "vk": "4", "cap": "0"},
    {"scan": "06", "vk": "5", "cap": "0"},
    {"scan": "07", "vk": "6", "cap": "0"},
    {"scan": "08", "vk": "7", "cap": "0"},
    {"scan": "09", "vk": "8", "cap": "0"},
    {"scan": "0A", "vk": "9", "cap": "0"},
    {"scan": "0B", "vk": "0", "cap": "0"},
    {"scan": "0C", "vk": "OEM_MINUS", "cap": "0"},
    {"scan": "0D", "vk": "OEM_PLUS", "cap": "0"},
    {"scan": "10", "vk": "Q", "cap": "0"},
    {"scan": "11", "vk": "W", "cap": "0"},
    {"scan": "12", "vk": "E", "cap": "0"},
    {"scan": "13", "vk": "R", "cap": "0"},
    {"scan": "14", "vk": "T", "cap": "0"},
    {"scan": "15", "vk": "Y", "cap": "0"},
    {"scan": "16", "vk": "U", "cap": "0"},
    {"scan": "17", "vk": "I", "cap": "0"},
    {"scan": "18", "vk": "O", "cap": "0"},
    {"scan": "19", "vk": "P", "cap": "0"},
    {"scan": "1A", "vk": "OEM_4", "cap": "0"},
    {"scan": "1B", "vk": "OEM_6", "cap": "0"},
    {"scan": "2B", "vk": "OEM_5", "cap": "0"},
    {"scan": "1E", "vk": "A", "cap": "0"},
    {"scan": "1F", "vk": "S", "cap": "0"},
    {"scan": "20", "vk": "D", "cap": "0"},
    {"scan": "21", "vk": "F", "cap": "0"},
    {"scan": "22", "vk": "G", "cap": "0"},
    {"scan": "23", "vk": "H", "cap": "0"},
    {"scan": "24", "vk": "J", "cap": "0"},
    {"scan": "25", "vk": "K", "cap": "0"},
    {"scan": "26", "vk": "L", "cap": "0"},
    {"scan": "27", "vk": "OEM_1", "cap": "0"},
    {"scan": "28", "vk": "OEM_7", "cap": "0"},
    {"scan": "2C", "vk": "Z", "cap": "0"},
    {"scan": "2D", "vk": "X", "cap": "0"},
    {"scan": "2E", "vk": "C", "cap": "0"},
    {"scan": "2F", "vk": "V", "cap": "0"},
    {"scan": "30", "vk": "B", "cap": "0"},
    {"scan": "31", "vk": "N", "cap": "0"},
    {"scan": "32", "vk": "M", "cap": "0"},
    {"scan": "33", "vk": "OEM_COMMA", "cap": "0"},
    {"scan": "34", "vk": "OEM_PERIOD", "cap": "0"},
    {"scan": "35", "vk": "OEM_2", "cap": "0"},
    {"scan": "39", "vk": "SPACE", "cap": "0"},
    {"scan": "53", "vk": "DECIMAL", "cap": "0"},
]

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

GUI_VERIFY_CANARY_KEY = "6"
GUI_VERIFY_CANARY_TOKEN = "0061"
GUI_VERIFY_DECIMAL_TOKEN = "002E"
DEFAULT_KEYBOARD_NAME = "Yinyuan"
DEFAULT_KEYBOARD_DESCRIPTION = "Chinese (Simplified) - Yinyuan"


def load_manual_assignments() -> dict[tuple[str, str], dict[str, str | None]]:
    payload = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    return {
        (entry["physical_key"], entry["output_layer"]): entry
        for entry in payload["layers"]
    }


def load_symbols() -> dict[str, str]:
    return json.loads(SYMBOL_PATH.read_text(encoding="utf-8"))


def load_bmp_projection_symbols() -> dict[str, str]:
    payload = json.loads(BMP_PROJECTION_PATH.read_text(encoding="utf-8"))
    used_mapping = payload.get("used_mapping", {})
    if not isinstance(used_mapping, dict):
        raise ValueError("bmp_pua_trial_projection.json missing used_mapping object")
    return {
        symbol_key: entry["char"]
        for symbol_key, entry in used_mapping.items()
        if isinstance(entry, dict) and entry.get("char")
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate yinyuan.klc from manual key layout using either BMP trial projection or canonical SPUA-B symbols."
    )
    parser.add_argument(
        "--symbol-mode",
        choices=("bmp-trial", "canonical"),
        default="bmp-trial",
        help="Symbol source for KLC generation. Default: bmp-trial",
    )
    parser.add_argument(
        "--ligature-mode",
        choices=("clean", "legacy"),
        default="clean",
        help="Whether to emit an empty LIGATURE section or keep the legacy MSKLC ligature rows. Default: clean",
    )
    parser.add_argument(
        "--keyboard-name",
        default=DEFAULT_KEYBOARD_NAME,
        help=f"Internal keyboard name used in the KBD header. Default: {DEFAULT_KEYBOARD_NAME}",
    )
    parser.add_argument(
        "--keyboard-description",
        default=DEFAULT_KEYBOARD_DESCRIPTION,
        help=f"Human-readable keyboard description used in the KBD header and DESCRIPTIONS section. Default: {DEFAULT_KEYBOARD_DESCRIPTION}",
    )
    return parser.parse_args()


def build_header_lines(keyboard_name: str, keyboard_description: str) -> list[str]:
    return [
        f'KBD\t{keyboard_name}\t"{keyboard_description}"',
        *HEADER_LINES[1:],
    ]


def load_symbols_for_mode(symbol_mode: str) -> tuple[dict[str, str], Path]:
    if symbol_mode == "bmp-trial":
        return load_bmp_projection_symbols(), BMP_PROJECTION_PATH
    return load_symbols(), SYMBOL_PATH


def build_standard_layout_rows() -> list[dict[str, str | None]]:
    return [dict(row) for row in STANDARD_LAYOUT_TEMPLATE]


def encode_token(char: str | None) -> str:
    if not char:
        return "%%"
    codepoint = ord(char)
    width = 6 if codepoint > 0xFFFF else 4
    return f"{codepoint:0{width}X}"


def resolve_key_code(vk_name: str) -> str | None:
    if vk_name in VK_TO_KEY_CODE:
        return VK_TO_KEY_CODE[vk_name]
    if len(vk_name) == 1 and vk_name.isalpha():
        return vk_name.lower()
    return None


def describe_entry(entry: dict[str, str | None] | None) -> str:
    if not entry:
        return "<none>"
    if entry.get("symbol_key"):
        return str(entry["symbol_key"])
    if entry.get("literal_char"):
        return str(entry["literal_char"])
    return "<none>"


def resolve_entry_char(entry: dict[str, str | None] | None, symbols: dict[str, str]) -> str | None:
    if not entry:
        return None
    symbol_key = entry.get("symbol_key")
    if symbol_key:
        return symbols.get(symbol_key)
    literal_char = entry.get("literal_char")
    if literal_char:
        return literal_char
    return None


def build_comment(
    key_code: str,
    base_entry: dict[str, str | None] | None,
    shift_entry: dict[str, str | None] | None,
    altgr_entry: dict[str, str | None] | None,
) -> str:
    return (
        f"{key_code} base={describe_entry(base_entry)} "
        f"shift={describe_entry(shift_entry)} altgr={describe_entry(altgr_entry)}"
    )


def build_keyname_section() -> list[str]:
    return [
        "KEYNAME",
        "",
        '01\tEsc',
        '0e\tBackspace',
        '0f\tTab',
        '1c\tEnter',
        '1d\tCtrl',
        '2a\tShift',
        '36\t"Right Shift"',
        '37\t"Num *"',
        '38\tAlt',
        '39\tSpace',
        '3a\t"Caps Lock"',
        '3b\tF1',
        '3c\tF2',
        '3d\tF3',
        '3e\tF4',
        '3f\tF5',
        '40\tF6',
        '41\tF7',
        '42\tF8',
        '43\tF9',
        '44\tF10',
        '45\t"Pause"',
        '46\t"Scroll Lock"',
        '47\t"Num 7"',
        '48\t"Num 8"',
        '49\t"Num 9"',
        '4a\t"Num -"',
        '4b\t"Num 4"',
        '4c\t"Num 5"',
        '4d\t"Num 6"',
        '4e\t"Num +"',
        '4f\t"Num 1"',
        '50\t"Num 2"',
        '51\t"Num 3"',
        '52\t"Num 0"',
        '53\t"Num Del"',
        '54\t"Sys Req"',
        '57\tF11',
        '58\tF12',
        '7c\tF13',
        '7d\tF14',
        '7e\tF15',
        '7f\tF16',
        '80\tF17',
        '81\tF18',
        '82\tF19',
        '83\tF20',
        '84\tF21',
        '85\tF22',
        '86\tF23',
        '87\tF24',
        '',
    ]


def build_keyname_ext_section() -> list[str]:
    return [
        "KEYNAME_EXT",
        "",
        '1c\t"Num Enter"',
        '1d\t"Right Ctrl"',
        '35\t"Num /"',
        '37\t"Prnt Scrn"',
        '38\t"Right Alt"',
        '45\t"Num Lock"',
        '46\tBreak',
        '47\tHome',
        '48\tUp',
        '49\t"Page Up"',
        '4b\tLeft',
        '4d\tRight',
        '4f\tEnd',
        '50\tDown',
        '51\t"Page Down"',
        '52\tInsert',
        '53\tDelete',
        '54\t<00>',
        '56\tHelp',
        '5b\t"Left Windows"',
        '5c\t"Right Windows"',
        '5d\tApplication',
        '',
    ]


def build_ligature_section(ligature_mode: str) -> list[str]:
    if ligature_mode == "clean":
        return [
            "LIGATURE",
            "",
            "//VK_   Mod#    Char0   Char1   Char2   Char3",
            "//----          ----    ----    ----    ----    ----",
            "",
        ]

    return [
        "LIGATURE",
        "",
        "//VK_   Mod#    Char0   Char1   Char2   Char3",
        "//----          ----    ----    ----    ----    ----",
        "",
        "0               0       006e    0301            // LATIN SMALL LETTER N + COMBINING ACUTE ACCENT",
        "7               0       01a8    0301            // LATIN SMALL LETTER TONE TWO + COMBINING ACUTE ACCENT",
        "8               0       01a8    0305            // LATIN SMALL LETTER TONE TWO + COMBINING OVERLINE",
        "9               0       01a8    0300            // LATIN SMALL LETTER TONE TWO + COMBINING GRAVE ACCENT",
        "C               0       028f    0305            // LATIN LETTER SMALL CAPITAL Y + COMBINING OVERLINE",
        "D               0       1d1c    0304            // LATIN LETTER SMALL CAPITAL U + COMBINING MACRON",
        "E               0       026a    0305            // LATIN LETTER SMALL CAPITAL I + COMBINING OVERLINE",
        "F               0       1d1c    0301            // LATIN LETTER SMALL CAPITAL U + COMBINING ACUTE ACCENT",
        "H               1       014b    0305            // LATIN SMALL LETTER ENG + COMBINING OVERLINE",
        "I               0       1d00    0304            // LATIN LETTER SMALL CAPITAL A + COMBINING MACRON",
        "J               0       1d0f    0301            // LATIN LETTER SMALL CAPITAL O + COMBINING ACUTE ACCENT",
        "J               1       db80    de7b    0301            // Legacy preserved ligature row",
        "K               0       1d0f    0304            // LATIN LETTER SMALL CAPITAL O + COMBINING MACRON",
        "K               1       db80    de7b    0304            // Legacy preserved ligature row",
        "L               0       1d0f    0300            // LATIN LETTER SMALL CAPITAL O + COMBINING GRAVE ACCENT",
        "L               1       db80    de7b    0300            // Legacy preserved ligature row",
        "M               0       1d07    0301            // LATIN LETTER SMALL CAPITAL E + COMBINING ACUTE ACCENT",
        "M               3       006d    00b4            // LATIN SMALL LETTER M + ACUTE ACCENT",
        "N               1       006e    0304            // LATIN SMALL LETTER N + COMBINING MACRON",
        "O               0       1d00    0300            // LATIN LETTER SMALL CAPITAL A + COMBINING GRAVE ACCENT",
        "R               0       026a    0301            // LATIN LETTER SMALL CAPITAL I + COMBINING ACUTE ACCENT",
        "S               0       1d1c    0300            // LATIN LETTER SMALL CAPITAL U + COMBINING GRAVE ACCENT",
        "U               0       1d00    0301            // LATIN LETTER SMALL CAPITAL A + COMBINING ACUTE ACCENT",
        "V               0       028f    0301            // LATIN LETTER SMALL CAPITAL Y + COMBINING ACUTE ACCENT",
        "W               0       026a    0300            // LATIN LETTER SMALL CAPITAL I + COMBINING GRAVE ACCENT",
        "X               0       028f    0300            // LATIN LETTER SMALL CAPITAL Y + COMBINING GRAVE ACCENT",
        "OEM_PLUS        0       014b    0301            // LATIN SMALL LETTER ENG + COMBINING ACUTE ACCENT",
        "OEM_COMMA       0       1d07    0304            // LATIN LETTER SMALL CAPITAL E + COMBINING MACRON",
        "OEM_COMMA       3       006d    02c9            // LATIN SMALL LETTER M + MODIFIER LETTER MACRON",
        "OEM_MINUS       0       006e    0300            // LATIN SMALL LETTER N + COMBINING GRAVE ACCENT",
        "OEM_PERIOD      0       1d07    0300            // LATIN LETTER SMALL CAPITAL E + COMBINING GRAVE ACCENT",
        "OEM_PERIOD      3       006d    02cb            // LATIN SMALL LETTER M + MODIFIER LETTER GRAVE ACCENT",
        "OEM_3           0       014b    0300            // LATIN SMALL LETTER ENG + COMBINING GRAVE ACCENT",
        "",
    ]


def build_description_sections(keyboard_description: str) -> list[str]:
    return [
        "DESCRIPTIONS",
        "",
        f'0409\t{keyboard_description}',
        "LANGUAGENAMES",
        "",
        '0409\tChinese (People\'s Republic of China)',
        "ENDKBD",
        "",
    ]


def build_layout_row(
    scan: str,
    vk: str,
    cap: str,
    state_0: str,
    state_1: str,
    state_2: str,
    state_6: str,
    comment: str,
) -> str:
    return f"{scan:<8}{vk:<16}{cap:<8}{state_0:<8}{state_1:<8}{state_2:<8}{state_6:<8}// {comment}"


def build_klc_text(
    rows: list[dict[str, str | None]],
    assignments: dict[tuple[str, str], dict[str, str | None]],
    symbols: dict[str, str],
    ligature_mode: str,
    keyboard_name: str,
    keyboard_description: str,
) -> str:
    updated_lines = build_header_lines(keyboard_name, keyboard_description)

    for row in rows:
        scan = str(row["scan"])
        vk = str(row["vk"])
        cap = str(row["cap"])
        key_code = resolve_key_code(vk)

        if vk == "DECIMAL":
            updated_lines.append(
                build_layout_row(
                    scan,
                    vk,
                    cap,
                    GUI_VERIFY_DECIMAL_TOKEN,
                    "-1",
                    "-1",
                    "-1",
                    "DECIMAL base=ASCII_PERIOD_FOR_GUI_VERIFY",
                )
            )
            continue

        if key_code == "space":
            updated_lines.append(build_layout_row(scan, vk, cap, "0020", "0020", "-1", "-1", "SPACE, SPACE, <none>, <none>"))
            continue
        if key_code is None:
            updated_lines.append(
                build_layout_row(
                    scan,
                    vk,
                    cap,
                    "%%",
                    "-1",
                    "-1",
                    "-1",
                    "template-pass-through",
                )
            )
            continue

        base_entry = assignments.get((key_code, "base"))
        shift_entry = assignments.get((key_code, "shift"))
        altgr_entry = assignments.get((key_code, "altgr"))

        base_char = resolve_entry_char(base_entry, symbols)
        shift_char = resolve_entry_char(shift_entry, symbols)
        altgr_char = resolve_entry_char(altgr_entry, symbols)
        state_0 = encode_token(base_char)
        state_1 = encode_token(shift_char)
        state_6 = encode_token(altgr_char) if altgr_char else "-1"
        comment = build_comment(key_code, base_entry, shift_entry, altgr_entry)

        # MSKLC GUI verify ignores PUA-only layouts and refuses setup packaging
        # unless it sees at least one ordinary printable key definition.
        if key_code == GUI_VERIFY_CANARY_KEY and state_0 == "%%" and state_1 == "%%":
            state_0 = GUI_VERIFY_CANARY_TOKEN
            comment = "6 base=GUI_CANARY_ASCII shift=<none> altgr=<none>"

        updated_lines.append(build_layout_row(scan, vk, cap, state_0, state_1, "-1", state_6, comment))

    updated_lines.append("")
    updated_lines.extend(build_ligature_section(ligature_mode))
    updated_lines.extend(build_keyname_section())
    updated_lines.extend(build_keyname_ext_section())
    updated_lines.extend(build_description_sections(keyboard_description))

    return "\r\n".join(updated_lines) + "\r\n"


def main() -> None:
    args = parse_args()
    assignments = load_manual_assignments()
    symbols, source_path = load_symbols_for_mode(args.symbol_mode)
    rows = build_standard_layout_rows()
    updated_text = build_klc_text(
        rows,
        assignments,
        symbols,
        args.ligature_mode,
        args.keyboard_name,
        args.keyboard_description,
    )
    with KLC_PATH.open("w", encoding="utf-16", newline="") as handle:
        handle.write(updated_text)
    print(
        f"Updated {KLC_PATH.name} from {LAYOUT_PATH.relative_to(ROOT)} "
        f"using {source_path.relative_to(ROOT)} ({args.symbol-mode if False else args.symbol_mode}, ligatures={args.ligature_mode}, name={args.keyboard_name}, description={args.keyboard_description})"
    )


if __name__ == "__main__":
    main()
