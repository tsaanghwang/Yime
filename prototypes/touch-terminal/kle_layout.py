#!/usr/bin/env python3
"""Strict, offline parser for the supported Yime subset of KLE JSON.

The KLE file owns touch presentation geometry only. Stable Yinyuan IDs are
embedded as exact key legends and are joined with canonical semantics later;
the file never defines Yinyuan-to-desktop-key projection.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any, Iterable

ID_PATTERN = re.compile(r"^[NM]\d{2}$")
COLOR_PATTERN = re.compile(r"^#[0-9a-fA-F]{6}$")
EPSILON = 1e-9


def _number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"KLE {name} must be a finite number")
    return float(value)


def _positive(value: Any, name: str) -> float:
    result = _number(value, name)
    if result <= 0:
        raise ValueError(f"KLE {name} must be positive")
    return result


def _color(value: Any, name: str) -> str:
    if not isinstance(value, str) or not COLOR_PATTERN.fullmatch(value):
        raise ValueError(f"KLE {name} must be #RRGGBB")
    return value.lower()


def _overlap(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return (
        min(left["x"] + left["width"], right["x"] + right["width"])
        - max(left["x"], right["x"]) > EPSILON
        and min(left["y"] + left["height"], right["y"] + right["height"])
        - max(left["y"], right["y"]) > EPSILON
    )


def parse_kle(template: Any, expected_ids: Iterable[str]) -> dict[str, Any]:
    """Parse strict KLE JSON into deterministic rectangular touch geometry.

    Supported KLE authoring features are rows, x/y offsets, rectangular w/h,
    colors and legends. Rotation, decals, stepped/homing caps and secondary
    rectangles are rejected because the touch renderer cannot preserve them.
    """
    if not isinstance(template, list) or not template:
        raise ValueError("KLE template must be a non-empty top-level array")
    expected = list(expected_ids)
    expected_set = set(expected)
    if len(expected) != len(expected_set):
        raise ValueError("Expected Yinyuan IDs contain duplicates")

    metadata: dict[str, Any] = {}
    start = 0
    if isinstance(template[0], dict):
        metadata = template[0]
        start = 1
    if not isinstance(metadata, dict):
        raise ValueError("KLE metadata must be an object")
    for field in ("name", "author", "notes"):
        if field in metadata and not isinstance(metadata[field], str):
            raise ValueError(f"KLE metadata {field} must be a string")

    rows = template[start:]
    if not rows or any(not isinstance(row, list) for row in rows):
        raise ValueError("KLE template rows must be arrays")

    keys: list[dict[str, Any]] = []
    seen: set[str] = set()
    row_y = 0.0
    color, text_color = "#e4eee7", "#172c30"
    unsupported_next = {"x2", "y2", "w2", "h2", "l", "n", "d"}
    unsupported_rotation = {"r", "rx", "ry"}

    for row_index, row in enumerate(rows):
        x, y = 0.0, row_y
        width, height = 1.0, 1.0
        for item in row:
            if isinstance(item, dict):
                if unsupported_next.intersection(item):
                    fields = ", ".join(sorted(unsupported_next.intersection(item)))
                    raise ValueError(f"Unsupported KLE key-shape properties: {fields}")
                for field in unsupported_rotation.intersection(item):
                    if abs(_number(item[field], field)) > EPSILON:
                        raise ValueError("Rotated KLE keys are not supported by the touch baseline")
                if "x" in item:
                    x += _number(item["x"], "x")
                if "y" in item:
                    y += _number(item["y"], "y")
                if "w" in item:
                    width = _positive(item["w"], "w")
                if "h" in item:
                    height = _positive(item["h"], "h")
                if "c" in item:
                    color = _color(item["c"], "c")
                if "t" in item:
                    text_color = _color(item["t"], "t")
                continue
            if not isinstance(item, str):
                raise ValueError("KLE rows may contain only property objects and key legend strings")
            legends = [legend.strip() for legend in item.split("\n")]
            ids = [legend for legend in legends if ID_PATTERN.fullmatch(legend)]
            if len(ids) != 1:
                raise ValueError(f"Each KLE key must contain exactly one exact Nxx/Mxx legend: {item!r}")
            yinyuan_id = ids[0]
            if yinyuan_id not in expected_set:
                raise ValueError(f"Unknown Yinyuan ID in KLE template: {yinyuan_id}")
            if yinyuan_id in seen:
                raise ValueError(f"Duplicate Yinyuan ID in KLE template: {yinyuan_id}")
            if x < -EPSILON or y < -EPSILON:
                raise ValueError(f"KLE key {yinyuan_id} has a negative position")
            key = {
                "id": yinyuan_id,
                "x": x,
                "y": y,
                "width": width,
                "height": height,
                "color": color,
                "textColor": text_color,
                "legends": legends,
                "row": row_index,
            }
            for other in keys:
                if _overlap(key, other):
                    raise ValueError(f"KLE keys overlap: {other['id']} and {yinyuan_id}")
            keys.append(key)
            seen.add(yinyuan_id)
            x += width
            width, height = 1.0, 1.0
        row_y += 1.0

    missing = expected_set - seen
    if missing:
        raise ValueError("KLE template is missing Yinyuan IDs: " + ", ".join(sorted(missing)))
    if len(keys) != len(expected):
        raise ValueError(f"KLE template must contain exactly {len(expected)} keys")
    max_x = max(key["x"] + key["width"] for key in keys)
    max_y = max(key["y"] + key["height"] for key in keys)
    return {
        "format": "keyboard-layout-editor.com",
        "unit": "kle-u",
        "metadata": {field: metadata[field] for field in ("name", "author", "notes") if field in metadata},
        "bounds": {"width": max_x, "height": max_y},
        "keys": keys,
    }


def load_kle(path: Path, expected_ids: Iterable[str]) -> tuple[dict[str, Any], str]:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    try:
        source = json.loads(text, object_pairs_hook=_unique_object)
    except json.JSONDecodeError as error:
        raise ValueError(f"KLE download must be strict JSON: {error}") from error
    parsed = parse_kle(source, expected_ids)
    return parsed, hashlib.sha256(text.encode("utf-8")).hexdigest()


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON member in KLE template: {key}")
        result[key] = value
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a downloaded Keyboard Layout Editor JSON file")
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    expected = [*(f"N{i:02d}" for i in range(1, 28)), *(f"M{i:02d}" for i in range(1, 34))]
    try:
        parsed, digest = load_kle(args.path, expected)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}")
        return 1
    bounds = parsed["bounds"]
    print(f"PASS: 60 stable IDs; bounds {bounds['width']:g} x {bounds['height']:g} KLE u; SHA-256 {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
