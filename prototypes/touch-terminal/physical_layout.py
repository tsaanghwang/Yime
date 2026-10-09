"""Generate a complete concept keyboard; manual_key_layout remains code authority.

KLE row offsets and label alignment match upstream serial.js. This intentionally
supports rectangular keyboards only and fails on unrenderable geometry.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

from kle_layout import _color, _number, _overlap, _positive, _unique_object, _reject_json_constant

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

# Serialized legend position -> normalized KLE position (0..8 top, 9..11 front).
LABEL_MAP = (
    (0, 6, 2, 8, 9, 11, 3, 5, 1, 4, 7, 10),
    (1, 7, -1, -1, 9, 11, 4, -1, -1, -1, -1, 10),
    (3, -1, 5, -1, 9, 11, -1, -1, 4, -1, -1, 10),
    (4, -1, -1, -1, 9, 11, -1, -1, -1, -1, -1, 10),
    (0, 6, 2, 8, 10, -1, 3, 5, 1, 4, 7, -1),
    (1, 7, -1, -1, 10, -1, 4, -1, -1, -1, -1, -1),
    (3, -1, 5, -1, 10, -1, -1, -1, 4, -1, -1, -1),
    (4, -1, -1, -1, 10, -1, -1, -1, -1, -1, -1, -1),
)
IDS = re.compile(r"[NM]\d{2}(?:\|[NM]\d{2})*")
HERE = Path(__file__).resolve().parent
SOURCE = HERE / "design/concept-129.kle.json"
OUTPUT = HERE / "data/physical-layout.json"
SHIFT_SYMBOLS = dict(zip("`1234567890-=[]\\;',./", '~!@#$%^&*()_+{}|:\"<>?'))


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def plain(value):
    parser = _Text()
    parser.feed(value)
    return "".join(parser.parts).strip()


def parse_physical_kle(source):
    if not isinstance(source, list) or not source:
        raise ValueError("KLE must be a nonempty array")
    has_metadata = isinstance(source[0], dict)
    metadata = source[0] if has_metadata else {}
    rows = source[1:] if has_metadata else source
    keys = []
    y = 0.0
    color, text_color, alignment = "#cccccc", "#000000", 4
    for row_index, row in enumerate(rows):
        if not isinstance(row, list):
            raise ValueError("KLE rows must be arrays")
        x, width, height = 0.0, 1.0, 1.0
        homing = False
        column = 0
        for item in row:
            if isinstance(item, dict):
                allowed = {"x", "y", "w", "h", "c", "t", "a", "n", "f", "f2", "fa", "p"}
                unknown = set(item) - allowed
                if unknown:
                    raise ValueError("Unsupported KLE geometry/properties: " + ", ".join(sorted(unknown)))
                x += _number(item.get("x", 0), "x")
                y += _number(item.get("y", 0), "y")
                width = _positive(item.get("w", width), "w")
                height = _positive(item.get("h", height), "h")
                if "c" in item:
                    color = _color(item["c"], "c")
                if "t" in item:
                    text_color = _color(item["t"], "t")
                if "a" in item:
                    alignment = item["a"]
                    if type(alignment) is not int or not 0 <= alignment <= 7:
                        raise ValueError("KLE alignment must be an integer from 0 to 7")
                if "n" in item:
                    if type(item["n"]) is not bool:
                        raise ValueError("KLE homing flag must be boolean")
                    homing = item["n"]
                continue
            if not isinstance(item, str):
                raise ValueError("KLE key legends must be strings")
            raw = item.split("\n")
            if len(raw) > 12:
                raise ValueError("KLE supports at most 12 legends per key")
            labels = [""] * 12
            ids = []
            for index, legend in enumerate(raw):
                pos = LABEL_MAP[alignment][index]
                if pos < 0 and legend:
                    raise ValueError("Legend cannot be represented by its KLE alignment")
                if pos >= 0:
                    labels[pos] = legend
                text = plain(legend)
                if IDS.fullmatch(text):
                    ids.extend(text.split("|"))
            if x < 0 or y < 0:
                raise ValueError("Negative key position")
            column += 1
            key = dict(id=f"R{row_index + 1:02d}K{column:02d}", x=x, y=y,
                       width=width, height=height, color=color, textColor=text_color,
                       labels=labels, alignment=alignment, homing=homing, yinyuanIds=ids)
            for other in keys:
                if _overlap(key, other):
                    raise ValueError(f"Overlapping keys: {other['id']} / {key['id']}")
            keys.append(key)
            x += width
            width = height = 1.0
            homing = False
        y += 1.0  # KLE y offsets persist into all following rows.
    if not keys:
        raise ValueError("No physical keys")
    return dict(metadata=metadata, keys=keys,
                bounds=dict(width=max(k["x"] + k["width"] for k in keys),
                            height=max(k["y"] + k["height"] for k in keys)))


def key_action(key, mapping, disabled):
    ids = key["yinyuanIds"]
    legends = [plain(label) for label in key["labels"]]
    if ids:
        active = [identifier for identifier in ids if identifier not in disabled]
        if not active or len({mapping[identifier] for identifier in ids}) != 1:
            raise ValueError(f"Key has no unambiguous active projection: {key['id']}")
        ascii_key = mapping[active[0]]
        if ascii_key not in legends:
            raise ValueError(f"KLE ASCII annotation disagrees with manual projection: {ids}")
        return dict(type="input", ascii=ascii_key)
    for label in legends:
        if re.fullmatch("⇧[1-9]", label):
            return dict(type="select", ordinal=int(label[1:]))
    if "PgUp" in legends and "9" not in legends:
        return dict(type="page", delta=-1)
    if "PgDn" in legends and "3" not in legends:
        return dict(type="page", delta=1)
    text = next((label for label in legends if label), "Space")
    actions = {"Esc": "clear", "Back Space": "backspace", "Enter": "confirm"}
    if text in actions:
        return dict(type=actions[text], **({"key": "Enter"} if text == "Enter" else {}))
    if text == "Space":
        return dict(type="confirm", key="Space")
    if text == "Shift":
        return dict(type="shift")
    names = {"Caps Lock": "CapsLock", "Num Lock": "NumLock", "Ctrl": "Control",
             "←": "ArrowLeft", "→": "ArrowRight", "↑": "ArrowUp", "↓": "ArrowDown"}
    if text in {"Win", "Menu", "PrtSc", "Scroll Lock", "Pause", "Break", "Ctrl", "Alt", "Caps Lock", "Num Lock", "Insert"} or re.fullmatch("F[0-9]+", text):
        return dict(type="unsupported", label=text)
    # Use the base legend on ordinary ANSI number/punctuation caps; keypad
    # navigation legends are not printable, so their top digit remains the base.
    if len(legends) > 6 and len(legends[6]) == 1 and ord(legends[6]) < 127:
        text = legends[6]
    if len(text) == 1 and 33 <= ord(text) <= 126:
        return dict(type="input", ascii=text)
    return dict(type="local", key=names.get(text, text))


def build(repo_root=ROOT, source_path=None):
    from yime.utils.yinyuan_id_chain import load_yinyuan_id_to_layout_key, layout_projection_digest
    source_path = source_path or repo_root / SOURCE.relative_to(ROOT)
    mapping = load_yinyuan_id_to_layout_key(repo_root)
    manual_path = repo_root / "internal_data/manual_key_layout.json"
    manual = json.loads(manual_path.read_text(encoding="utf-8-sig"))
    disabled = set(manual.get("disabled_yinyuan_ids", []))
    if disabled != {"M25", "M26", "M27"}:
        raise ValueError("Concept experiment requires explicit M25-M27 disabled policy")
    raw = source_path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    parsed = parse_physical_kle(json.loads(raw, object_pairs_hook=_unique_object, parse_constant=_reject_json_constant))
    seen = [identifier for key in parsed["keys"] for identifier in key["yinyuanIds"]]
    if len(seen) != len(set(seen)) or set(seen) != set(mapping):
        raise ValueError("Physical board must show every canonical ID exactly once")
    groups = {frozenset(("M28", "M25")), frozenset(("M29", "M26")), frozenset(("M30", "M27"))}
    actual = {frozenset(k["yinyuanIds"]) for k in parsed["keys"] if len(k["yinyuanIds"]) > 1}
    if actual != groups:
        raise ValueError("Unexpected physical shared-key groups")
    for key in parsed["keys"]:
        key["disabledYinyuanIds"] = sorted(set(key["yinyuanIds"]) & disabled)
        key["action"] = key_action(key, mapping, disabled)
        if key["action"]["type"] == "select":
            # Keep the frozen KLE legends as provenance. Dedicated concept keys
            # show plain ordinals; they do not emulate an ANSI Shift chord.
            key["displayLabels"] = [""] * 12
            key["displayLabels"][4] = str(key["action"]["ordinal"])
        elif any(plain(label) in {"前页", "后页"} for label in key["labels"]):
            key["displayLabels"] = ["" if plain(label) in {"前页", "后页"} else label for label in key["labels"]]
        base = str(key["action"]["ordinal"]) if key["action"]["type"] == "select" else key["action"].get("ascii")
        if base in SHIFT_SYMBOLS:
            key["shiftAction"] = dict(type="input", ascii=SHIFT_SYMBOLS[base])
    candidates = [key["action"]["ordinal"] for key in parsed["keys"] if key["action"]["type"] == "select"]
    if sorted(candidates) != list(range(1, 10)) or len(parsed["keys"]) != 129:
        raise ValueError("Expected full 129-key concept board with nine candidate actions")
    geometry = json.dumps(parsed, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    manual_text = manual_path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    return dict(formatVersion=2, layoutId=layout_projection_digest(repo_root),
                touchTemplateId=hashlib.sha256(geometry.encode()).hexdigest(),
                name="Yime ASCII concept keyboard · 129 keys", bounds=parsed["bounds"],
                disabledYinyuanIds=sorted(disabled), keys=parsed["keys"],
                policyNote="M25、M26、M27 为未来预留音元，当前停用，不参与编码和候选输出。",
                sources=[dict(path=source_path.relative_to(repo_root).as_posix(), sha256=hashlib.sha256(raw.encode()).hexdigest()),
                         dict(path=manual_path.relative_to(repo_root).as_posix(), sha256=hashlib.sha256(manual_text.encode()).hexdigest())])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != output:
            raise SystemExit("FAIL: regenerate physical-layout.json")
    else:
        OUTPUT.write_text(output, encoding="utf-8", newline="\n")
    print("PASS: 129 physical keys, 60 IDs / 57 active, 9 candidate/digit positions and one-shot symbol Shift")


if __name__ == "__main__":
    main()
