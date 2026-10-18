"""Generate physical KLE geometry with explicit legend actions and one manual projection."""
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

# Serialized legend position -> normalized KLE position.
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
IDS = re.compile(r"[NMR]\d{2}")
HERE = Path(__file__).resolve().parent
SOURCE = HERE / "design/keyboard-layout.json"
OUTPUT = HERE / "data/physical-layout.json"


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def plain(value):
    if len(value.strip()) == 1:
        return value.strip()  # Literal '<' is an ASCII key, not an HTML tag.
    parser = _Text()
    parser.feed(value)
    return "".join(parser.parts).strip()


def absolute_rectangles(key):
    return [dict(x=key["x"] + rect["x"], y=key["y"] + rect["y"],
                 width=rect["width"], height=rect["height"]) for rect in key["rectangles"]]


def keys_overlap(first, second):
    return any(_overlap(a, b) for a in absolute_rectangles(first) for b in absolute_rectangles(second))


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
        x2 = y2 = 0.0
        width2 = height2 = None
        homing = False
        column = 0
        for item in row:
            if isinstance(item, dict):
                allowed = {"x", "y", "w", "h", "x2", "y2", "w2", "h2",
                           "c", "t", "a", "n", "f", "f2", "fa", "p"}
                unknown = set(item) - allowed
                if unknown:
                    raise ValueError("Unsupported KLE geometry/properties: " + ", ".join(sorted(unknown)))
                x += _number(item.get("x", 0), "x")
                y += _number(item.get("y", 0), "y")
                if "w" in item:
                    width = width2 = _positive(item["w"], "w")
                if "h" in item:
                    height = height2 = _positive(item["h"], "h")
                if "w2" in item:
                    width2 = _positive(item["w2"], "w2")
                if "h2" in item:
                    height2 = _positive(item["h2"], "h2")
                x2 = _number(item.get("x2", x2), "x2")
                y2 = _number(item.get("y2", y2), "y2")
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
                    ids.append(text)
            primary = dict(x=0.0, y=0.0, width=width, height=height)
            secondary = dict(x=x2, y=y2, width=width2 or width, height=height2 or height)
            rectangles = [primary] if secondary == primary else [primary, secondary]
            column += 1
            key = dict(id=f"R{row_index + 1:02d}K{column:02d}", x=x, y=y,
                       width=width, height=height, rectangles=rectangles,
                       color=color, textColor=text_color, labels=labels,
                       alignment=alignment, homing=homing, yinyuanIds=ids)
            if any(rect["x"] < 0 or rect["y"] < 0 for rect in absolute_rectangles(key)):
                raise ValueError("Negative key position")
            for other in keys:
                if keys_overlap(key, other):
                    raise ValueError(f"Overlapping keys: {other['id']} / {key['id']}")
            keys.append(key)
            # KLE secondary geometry never advances the row cursor.
            x += width
            width = height = 1.0
            x2 = y2 = 0.0
            width2 = height2 = None
            homing = False
        y += 1.0
    if not keys:
        raise ValueError("No physical keys")
    rects = [rect for key in keys for rect in absolute_rectangles(key)]
    return dict(metadata=metadata, keys=keys,
                bounds=dict(width=max(r["x"] + r["width"] for r in rects),
                            height=max(r["y"] + r["height"] for r in rects)))


def _ascii(text):
    return len(text) == 1 and 33 <= ord(text) <= 126


def _layer_action(identifier, annotation, mapping):
    if IDS.fullmatch(identifier):
        if mapping.get(identifier) != annotation:
            raise ValueError(f"KLE ASCII annotation disagrees with manual projection: {identifier}")
        return dict(type="input", ascii=annotation)
    if _ascii(annotation):
        return dict(type="input", ascii=annotation)
    if _ascii(identifier):
        return dict(type="input", ascii=identifier)
    return None


def _actions(key, mapping):
    labels = [plain(label) for label in key["labels"]]
    text = next((label for label in labels if label), "Space")
    controls = {
        "Esc": dict(type="clear"), "Back Space": dict(type="backspace"),
        "Enter": dict(type="confirm", key="Enter"), "Space": dict(type="confirm", key="Space"),
        "Shift": dict(type="shift"), "中英文切换": dict(type="toggle-language"),
        "中英标点切换": dict(type="toggle-punctuation"),
    }
    if text in controls:
        key["action"] = controls[text]
        return
    if key["zone"] != "main":
        if text == "Num Lock":
            key["action"] = dict(type="toggle-number")
            return
        if not _ascii(text) or text not in "0123456789./*-+":
            raise ValueError(f"Unsupported side-zone legend: {text}")
        key["action"] = dict(type="literal", ascii=text)
        edit = {"Home": "Home", "↑": "ArrowUp", "PgUp": "PageUp",
                "←": "ArrowLeft", "→": "ArrowRight", "End": "End",
                "↓": "ArrowDown", "PgDn": "PageDown", "Ins": "Insert", "Del": "Delete"}
        if labels[6] in edit:
            key["editAction"] = dict(type="local", key=edit[labels[6]])
        elif text == "5":
            key["editAction"] = dict(type="noop")
        elif text in "/-*+" and not labels[6]:
            key["editAction"] = dict(key["action"])
        else:
            raise ValueError(f"Missing or unknown numeric editing legend: {key['id']}")
        return
    base = _layer_action(labels[6], labels[8], mapping)
    shifted = _layer_action(labels[0], labels[2], mapping)
    key["baseYinyuanIds"] = [labels[6]] if IDS.fullmatch(labels[6]) else []
    key["shiftYinyuanIds"] = [labels[0]] if IDS.fullmatch(labels[0]) else []
    if base:
        key["action"] = base
        if shifted:
            key["shiftAction"] = shifted
        return
    # No inferred ANSI upper layer: centered characters are single actions.
    if _ascii(text):
        key["action"] = dict(type="input", ascii=text)
    elif text == "Tab":
        key["action"] = dict(type="local", key="Tab")
    else:
        key["action"] = dict(type="unsupported", label=text)


def build(repo_root=ROOT, source_path=None):
    from yime.utils.yinyuan_id_chain import load_input_id_to_layout_key, layout_projection_digest
    source_path = source_path or repo_root / SOURCE.relative_to(ROOT)
    mapping = load_input_id_to_layout_key(repo_root)
    manual_path = repo_root / "internal_data/manual_key_layout.json"
    manual = json.loads(manual_path.read_text(encoding="utf-8-sig"))
    if manual.get("disabled_yinyuan_ids") or manual.get("shared_yinyuan_key_groups"):
        raise ValueError("The reviewed 138-key layout requires all 75 carriers independent and enabled")
    raw = source_path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    parsed = parse_physical_kle(json.loads(raw, object_pairs_hook=_unique_object, parse_constant=_reject_json_constant))
    seen = [identifier for key in parsed["keys"] for identifier in key["yinyuanIds"]]
    if len(seen) != len(set(seen)) or set(seen) != set(mapping):
        raise ValueError("Physical board must show every input ID exactly once")
    locks = sorted(key["x"] for key in parsed["keys"] if "Num Lock" in map(plain, key["labels"]))
    if len(locks) != 2 or locks[0] != 0 or locks[1] + 3 != parsed["bounds"]["width"]:
        raise ValueError("Expected independent left/right three-column numeric zones")
    aliases = manual.get("input_id_aliases", {})
    for key in parsed["keys"]:
        key["zone"] = "left" if key["x"] < 3 else "right" if key["x"] >= locks[1] else "main"
        key["disabledYinyuanIds"] = []
        _actions(key, mapping)
        key_aliases = {alias: target for alias, target in aliases.items() if target in key["yinyuanIds"]}
        if key_aliases:
            key["inputIdAliases"] = key_aliases
            key["displayLabels"] = [
                label + "/" + "/".join(alias for alias, target in key_aliases.items() if target == plain(label))
                if plain(label) in key_aliases.values() else label for label in key["labels"]]
    if len(parsed["keys"]) != 138:
        raise ValueError("Expected full 138-key concept board")
    reachable = {action["ascii"] for key in parsed["keys"] for name in ("action", "shiftAction")
                 if (action := key.get(name, {})).get("type") == "input"}
    if reachable != {chr(value) for value in range(33, 127)}:
        raise ValueError("Main keyboard must explicitly reach every printable non-space ASCII character")
    geometry = json.dumps(parsed, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    manual_text = manual_path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    return dict(formatVersion=3, layoutId=layout_projection_digest(repo_root),
                touchTemplateId=hashlib.sha256(geometry.encode()).hexdigest(),
                name="Yime ASCII concept keyboard · 138 keys", bounds=parsed["bounds"],
                disabledYinyuanIds=[], inputIdAliases=aliases, keys=parsed["keys"],
                policyNote=parsed["metadata"].get("notes", ""),
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
    print("PASS: 138 physical keys, 75 independent input IDs, explicit layers and dual numeric zones")


if __name__ == "__main__":
    main()
