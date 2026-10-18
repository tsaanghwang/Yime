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
SOURCE = HERE / "design/yime-cn-134k-24u-keyboard-layout.json"
ENGLISH_SOURCE = HERE / "design/yime-en-134k-24u-keyboard-layout.json"
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
    text = next((label for label in labels if label), "")
    controls = {
        "Esc": dict(type="clear"), "Back Space": dict(type="backspace"),
        "Enter": dict(type="confirm", key="Enter"), "Space": dict(type="confirm", key="Space"),
        "Shift": dict(type="shift"), "CN EN": dict(type="toggle-language"),
        "Layout": dict(type="toggle-layout"),
    }
    # Numeric Enter has a lower 'Enter' legend and an upper '=' legend.
    if key["zone"] != "main" and "Enter" in labels:
        key["action"] = dict(type="confirm", key="Enter")
        return
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
        edit = {"Home":"Home", "↑":"ArrowUp", "PgUp":"PageUp", "←":"ArrowLeft",
                "→":"ArrowRight", "End":"End", "↓":"ArrowDown", "PgDn":"PageDown",
                "Ins":"Insert", "Del":"Delete"}
        secondary = labels[7] or labels[6]
        if secondary in edit:
            key["editAction"] = dict(type="local", key=edit[secondary])
        elif text == "5":
            key["editAction"] = dict(type="noop")
        elif text in "/-*+" and not secondary:
            key["editAction"] = dict(key["action"])
        else:
            raise ValueError(f"Missing numeric editing legend: {key['id']}")
        return
    base = _layer_action(labels[6], labels[8], mapping)
    shifted = _layer_action(labels[0], labels[2], mapping)
    # Reviewed CN literal-only upper positions include six Unicode symbols.
    upper = labels[2] or labels[0]
    if not shifted and upper in {"·", "、", "—", "×", "√", "÷"}:
        shifted = dict(type="symbol", ascii=upper)
    key["baseYinyuanIds"] = [labels[6]] if IDS.fullmatch(labels[6]) else []
    key["shiftYinyuanIds"] = [labels[0]] if IDS.fullmatch(labels[0]) else []
    if base:
        key["action"] = base
        if shifted:
            key["shiftAction"] = shifted
        # Unlabelled ASCII punctuation layers are the reserved optional literal
        # entrances. Coding-ID layers always retain their encoding action.
        for field, id_field in (("action","baseYinyuanIds"),("shiftAction","shiftYinyuanIds")):
            action = key.get(field, {})
            char = action.get("ascii", "")
            if not key[id_field] and len(char) == 1 and not char.isalnum() and _ascii(char):
                action["literalEntry"] = True
        return
    if text == "Tab":
        key["action"] = dict(type="local", key="Tab")
    else:
        key["action"] = dict(type="unsupported", label=text or "System key")


def _english_action(key):
    labels = [plain(label) for label in key["labels"]]
    # Only truly empty KLE strings are disabled. Icon-only system keys retain
    # their schematic control identity and never become spaces.
    if not any(key["labels"]):
        return dict(labels=key["labels"], action=dict(type="disabled"), disabled=True)
    if key["zone"] != "main" or any(label in {"Esc","Back Space","Enter","Space","Shift","CN EN","Layout","Tab"} for label in labels):
        _actions(key, {})
        return {field:key[field] for field in ("labels","action","editAction") if field in key}
    base, upper = labels[7], labels[1]
    if _ascii(base):
        result = dict(labels=key["labels"], action=dict(type="input", ascii=base))
        if _ascii(upper):
            result["shiftAction"] = dict(type="input", ascii=upper)
        return result
    _actions(key, {})
    return dict(labels=key["labels"],action=key["action"])


def build(repo_root=ROOT, source_path=None):
    from tools.ascii_keyboard.layout_chain import load_input_id_to_layout_key, layout_projection_digest
    source_path = source_path or repo_root / SOURCE.relative_to(ROOT)
    english_path = repo_root / ENGLISH_SOURCE.relative_to(ROOT)
    mapping = load_input_id_to_layout_key(repo_root)
    manual_path = repo_root / "prototypes/touch-terminal/encoding/manual_key_layout.json"
    manual = json.loads(manual_path.read_text(encoding="utf-8-sig"))
    if manual.get("disabled_yinyuan_ids") or manual.get("shared_yinyuan_key_groups"):
        raise ValueError("CN134 requires all 75 carriers independent and enabled")
    def read(path):
        raw = path.read_text(encoding="utf-8-sig").replace("\r\n","\n").replace("\r","\n")
        return raw, parse_physical_kle(json.loads(raw,object_pairs_hook=_unique_object,parse_constant=_reject_json_constant))
    raw, parsed = read(source_path)
    english_raw, english = read(english_path)
    seen = [identifier for key in parsed["keys"] for identifier in key["yinyuanIds"]]
    if len(seen) != len(set(seen)) or set(seen) != set(mapping):
        raise ValueError("Physical board must show every input ID exactly once")
    locks = sorted(key["x"] for key in parsed["keys"] if "Num Lock" in map(plain,key["labels"]))
    if len(locks) != 2 or locks[0] != 0 or locks[1]+3 != parsed["bounds"]["width"]:
        raise ValueError("Expected independent left/right three-column numeric zones")
    if len(parsed["keys"]) != 134 or len(english["keys"]) != 134:
        raise ValueError("Expected two full 134-key concept boards")
    geometry_fields = ("id","x","y","width","height","rectangles","homing")
    aliases = manual.get("input_id_aliases",{})
    for key, en in zip(parsed["keys"],english["keys"]):
        if any(key[field] != en[field] for field in geometry_fields):
            raise ValueError("CN/EN geometry must match for node reuse")
        key["zone"] = en["zone"] = "left" if key["x"] < 3 else "right" if key["x"] >= locks[1] else "main"
        key["disabledYinyuanIds"] = []
        _actions(key,mapping)
        key_aliases = {a:t for a,t in aliases.items() if t in key["yinyuanIds"]}
        if key_aliases:
            key["inputIdAliases"] = key_aliases
        key["english"] = _english_action(en)
    if sum(key["english"].get("disabled",False) for key in parsed["keys"]) != 23:
        raise ValueError("EN134 must explicitly disable exactly 23 blank keys")
    for variant in (None,"english"):
        reachable = {action["ascii"] for key in parsed["keys"] for name in ("action","shiftAction")
                     if (action := (key[variant] if variant else key).get(name,{})).get("type") == "input"}
        if not {chr(value) for value in range(33,127)} <= reachable:
            raise ValueError("Each main keyboard must reach all non-space ASCII")
    geometry = json.dumps(parsed,ensure_ascii=False,sort_keys=True,separators=(",",":"))
    sources = [dict(path=path.relative_to(repo_root).as_posix(),sha256=hashlib.sha256(content.encode()).hexdigest())
               for path,content in ((source_path,raw),(english_path,english_raw),(manual_path,manual_path.read_text(encoding="utf-8-sig").replace("\r\n","\n")))]
    return dict(formatVersion=4,layoutId=layout_projection_digest(repo_root),
                touchTemplateId=hashlib.sha256(geometry.encode()).hexdigest(),
                name="Yime ASCII concept keyboard · CN/EN 134 keys",bounds=parsed["bounds"],
                disabledYinyuanIds=[],inputIdAliases=aliases,keys=parsed["keys"],
                policyNote=parsed["metadata"].get("notes",""),englishPolicyNote=english["metadata"].get("notes",""),sources=sources)


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
    print("PASS: CN/EN 134 physical keys, 75 input IDs, 23 disabled English keys and identical geometry")


if __name__ == "__main__":
    main()
